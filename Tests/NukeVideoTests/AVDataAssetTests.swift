// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import AVFoundation
@testable import NukeVideo

#if !os(watchOS)

/// `AVDataAsset` serves a video from memory through a resource loader that
/// answers AVFoundation's content information and byte-range requests. The
/// file-based asset for the same bytes is the reference it has to match.
@Suite(.timeLimit(.minutes(5)))
struct AVDataAssetTests {
    @Test(arguments: [AVFileType.mp4, .mov, .m4v])
    func loadsSameMetadataAsFileAsset(fileType: AVFileType) async throws {
        // Given
        let fixture = VideoFixture(width: 48, height: 32, frameCount: 10, fileType: fileType)
        let url = try await fixture.makeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)

        // When
        let reference = AVURLAsset(url: url)
        let asset = AVDataAsset(data: data, type: AssetType(rawValue: fileType.rawValue))

        // Then
        #expect(try await asset.load(.isPlayable))
        #expect(try await asset.load(.isReadable))
        #expect(try await asset.load(.duration) == reference.load(.duration))
        #expect(try await asset.load(.duration) == fixture.duration)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let referenceTrack = try #require(try await reference.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 48, height: 32))
        #expect(try await track.load(.nominalFrameRate) == referenceTrack.load(.nominalFrameRate))
    }

    /// Reads every compressed sample through the resource loader and compares
    /// the bytes with the ones read from the file: a byte range answered with
    /// the wrong bytes, or cut short, shows up here. The video is laid out for
    /// progressive download, so that the last sample ends at the last byte.
    @Test(arguments: [true, false])
    func servesExactBytesOfEverySample(isFastStart: Bool) async throws {
        // Given
        let fixture = VideoFixture(width: 64, height: 64, frameCount: 30, isFastStart: isFastStart) {
            // A different color for every frame, so that no two samples are alike.
            (UInt8(($0 * 37) % 256), UInt8(($0 * 91) % 256), UInt8(($0 * 13) % 256))
        }
        let url = try await fixture.makeFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)

        // When
        let expected = try await readSamples(of: AVURLAsset(url: url))
        let samples = try await readSamples(of: AVDataAsset(data: data, type: .mp4))

        // Then
        #expect(expected.count >= fixture.frameCount)
        #expect(samples.count == expected.count)
        #expect(samples == expected)
    }

    /// The content type is derived from the asset type, and anything that
    /// isn't a known video container is served as MP4.
    @Test(arguments: [AssetType?.none, .jpeg])
    func servesDataOfUnknownTypeAsMP4(type: AssetType?) async throws {
        // Given
        let data = try await VideoFixture(frameCount: 3).makeData()

        // When
        let asset = AVDataAsset(data: data, type: type)

        // Then
        #expect(try await asset.load(.isPlayable))
        #expect(try await asset.load(.duration) == CMTime(value: 3, timescale: 30))
    }

    /// The resource loader keeps only a weak reference to its delegate, so the
    /// asset has to be the one keeping it alive for as long as it is used.
    @Test func keepsResourceLoaderDelegateAlive() async throws {
        // Given
        let data = try await VideoFixture(frameCount: 3).makeData()

        // When
        let asset = AVDataAsset(data: data, type: .mp4)

        // Then
        #expect(asset.resourceLoader.delegate != nil)
        #expect(asset.resourceLoader.delegateQueue != nil)
        #expect(try await asset.load(.isPlayable))
        #expect(asset.resourceLoader.delegate != nil)
    }

    @Test func assetsHaveDistinctURLs() async throws {
        // Given
        let data = try await VideoFixture(frameCount: 3).makeData()

        // When
        let first = AVDataAsset(data: data, type: .mp4)
        let second = AVDataAsset(data: data, type: .mp4)

        // Then the scheme is one that AVFoundation can't load by itself, so
        // every request goes to the resource loader
        #expect(first.url != second.url)
        #expect(first.url.scheme == "in-memory-data")
        #expect(!first.url.isFileURL)
    }
}

/// Returns the bytes of every compressed sample of the video track, in decode order.
private func readSamples(of asset: AVAsset) async throws -> [Data] {
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
    reader.add(output)
    #expect(reader.startReading())
    var samples: [Data] = []
    while let buffer = output.copyNextSampleBuffer() {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else {
            continue // A marker without media data
        }
        var bytes = Data(count: CMBlockBufferGetDataLength(blockBuffer))
        let status = bytes.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: $0.count, destination: $0.baseAddress!)
        }
        #expect(status == kCMBlockBufferNoErr)
        samples.append(bytes)
    }
    #expect(reader.status == .completed, "\(String(describing: reader.error))")
    return samples
}

#endif
