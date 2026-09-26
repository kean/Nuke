// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import AVFoundation
import NukeVideo

#if !os(watchOS) && !os(visionOS)

@Suite(.timeLimit(.minutes(5)))
struct VideoDecoderTests {

    // MARK: Initialization

    @Test(arguments: [AVFileType.mp4, .mov, .m4v])
    func acceptsVideoContainers(fileType: AVFileType) async throws {
        // Given
        let data = try await VideoFixture(fileType: fileType).makeData()

        // When
        let decoder = try #require(ImageDecoders.Video(context: .mock(data: data)))
        let container = try decoder.decode(data)

        // Then
        #expect(decoder.isAsynchronous)
        #expect(container.type == AssetType(rawValue: fileType.rawValue))
        #expect(container.type?.isVideo == true)
    }

    /// The decoder is picked by sniffing the `ftyp` box alone, before any of
    /// the video has arrived, so that the pipeline can hand it the first chunk.
    @Test(arguments: ["isom", "mp42", "avc1", "M4V ", "qt  "])
    func acceptsHeaderOfVideoBrand(brand: String) {
        #expect(ImageDecoders.Video(context: .mock(data: Test.fileTypeBox(brands: [brand]))) != nil)
    }

    /// ISO base media files that aren't video share the `ftyp` box with the
    /// ones that are, so the brand is what tells them apart.
    @Test(arguments: ["heic", "avif", "mif1", "M4A "])
    func rejectsHeaderOfNonVideoBrand(brand: String) {
        #expect(ImageDecoders.Video(context: .mock(data: Test.fileTypeBox(brands: [brand]))) == nil)
    }

    @Test func rejectsDataThatIsNotVideo() {
        let samples: [Data] = [
            Data(),
            Data([0xFF, 0xD8, 0xFF, 0xE0]), // JPEG
            Test.png(chunks: []),
            Data("GIF89a".utf8),
            // The major brand ends at byte 12: one byte short isn't a video yet.
            Test.fileTypeBox(brands: ["isom"]).prefix(11)
        ]
        for data in samples {
            #expect(ImageDecoders.Video(context: .mock(data: data)) == nil, "\(Array(data))")
        }
    }

    // MARK: Decoding

    /// Regression test for https://github.com/kean/Nuke/issues/811 and for
    /// `.videoAssetKey` missing from the container.
    @Test func decodeReturnsFirstFrameAndPlayableAsset() async throws {
        // Given a video whose first frame is red and the rest are blue
        let fixture = VideoFixture(width: 32, height: 16)
        let data = try await fixture.makeData()
        let decoder = try #require(ImageDecoders.Video(context: .mock(data: data)))

        // When
        let container = try decoder.decode(data)

        // Then the image is the first frame at the video's pixel size
        let image = try #require(container.image.cgImage)
        #expect(image.width == 32)
        #expect(image.height == 16)
        let color = try #require(RGBABitmap(cgImage: image)).color(atX: image.width / 2, y: image.height / 2)
        #expect(color.red > 150 && color.blue < 100, "\(color)")

        // Then the container describes the video and keeps its data
        #expect(!container.isPreview)
        #expect(container.type == .mp4)
        #expect(container.data == data)

        // Then the asset plays the video from memory
        let asset = try #require(container.userInfo[.videoAssetKey] as? AVAsset)
        #expect(try await asset.load(.isPlayable))
        #expect(try await asset.load(.duration) == fixture.duration)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 32, height: 16))
    }

    /// Each decode attaches an asset of its own that plays its own data.
    @Test func decodedAssetsAreIndependent() async throws {
        // Given two videos of different lengths
        let short = try await VideoFixture(frameCount: 3).makeData()
        let long = try await VideoFixture(frameCount: 12).makeData()

        // When
        let first = try #require(ImageDecoders.Video(context: .mock(data: short))).decode(short)
        let second = try #require(ImageDecoders.Video(context: .mock(data: long))).decode(long)

        // Then
        let firstAsset = try #require(first.userInfo[.videoAssetKey] as? AVAsset)
        let secondAsset = try #require(second.userInfo[.videoAssetKey] as? AVAsset)
        #expect(firstAsset !== secondAsset)
        #expect(try await firstAsset.load(.duration) == CMTime(value: 3, timescale: 30))
        #expect(try await secondAsset.load(.duration) == CMTime(value: 12, timescale: 30))
    }

    /// When no frame can be decoded, `decode` still succeeds: the image is
    /// empty and the asset is attached, leaving it to the player to decide
    /// whether there is anything to play.
    @Test func decodeWithoutDecodableFrameReturnsEmptyImage() throws {
        // Given the header of an MP4 file and nothing after it
        let data = Test.fileTypeBox(brands: ["isom"])
        let decoder = try #require(ImageDecoders.Video(context: .mock(data: data)))

        // When
        let container = try decoder.decode(data)

        // Then
        #expect(container.image.size == .zero)
        #expect(container.type == .mp4)
        #expect(container.userInfo[.videoAssetKey] is AVAsset)
    }

    // MARK: Partially Downloaded Data

    @Test func partialDecodeProducesOnePreview() async throws {
        // Given
        let data = try await VideoFixture().makeData()
        let decoder = try #require(ImageDecoders.Video(context: .mock(data: data, isCompleted: false)))

        // When
        let preview = try #require(decoder.decodePartiallyDownloadedData(data))

        // Then the preview is the first frame, and it is marked as a preview
        #expect(preview.isPreview)
        #expect(preview.type == .mp4)
        #expect(preview.data == data)
        #expect(preview.userInfo[.videoAssetKey] is AVAsset)
        let image = try #require(preview.image.cgImage)
        #expect(image.width == 32 && image.height == 16)

        // Then the decoder produces no more previews, whatever data it gets
        #expect(decoder.decodePartiallyDownloadedData(data) == nil)
        let other = try await VideoFixture(frameCount: 3).makeData()
        #expect(decoder.decodePartiallyDownloadedData(other) == nil)

        // Then the final decode is unaffected by the preview
        let container = try decoder.decode(data)
        #expect(!container.isPreview)
        #expect(container.image.cgImage?.width == 32)
    }

    /// A video that isn't laid out for progressive download has its movie
    /// header at the end, so no frame can be decoded until the download
    /// completes. The attempts that fail must not use up the one preview.
    @Test func partialDecodeRetriesUntilFrameIsAvailable() async throws {
        // Given
        let data = try await VideoFixture(isFastStart: false).makeData()
        let decoder = try #require(ImageDecoders.Video(context: .mock(data: data.prefix(64), isCompleted: false)))

        // When the data doesn't have a decodable frame yet
        #expect(decoder.decodePartiallyDownloadedData(data.prefix(64)) == nil)
        #expect(decoder.decodePartiallyDownloadedData(data.prefix(data.count - 1)) == nil)

        // Then a later call with enough data still produces the preview
        let preview = try #require(decoder.decodePartiallyDownloadedData(data))
        #expect(preview.isPreview)
    }

    /// With the movie header in front of the samples, the first frame can be
    /// shown before the rest of the video arrives.
    @Test func partialDecodeOfFastStartVideoProducesPreviewBeforeDownloadCompletes() async throws {
        // Given the first 90% of a video laid out for progressive download
        let data = try await VideoFixture(frameCount: 90, isFastStart: true).makeData()
        let partial = data.prefix(data.count * 9 / 10)
        let decoder = try #require(ImageDecoders.Video(context: .mock(data: partial, isCompleted: false)))

        // When
        let preview = try #require(decoder.decodePartiallyDownloadedData(partial))

        // Then
        #expect(preview.isPreview)
        #expect(preview.data == partial)
        let image = try #require(preview.image.cgImage)
        #expect(image.width == 32 && image.height == 16)
        let color = try #require(RGBABitmap(cgImage: image)).color(atX: image.width / 2, y: image.height / 2)
        #expect(color.red > 150 && color.blue < 100, "\(color)")
    }

    @Test func partialDecodeIgnoresDataThatIsNotVideo() async throws {
        // Given
        let data = try await VideoFixture().makeData()
        let decoder = try #require(ImageDecoders.Video(context: .mock(data: data, isCompleted: false)))

        // When
        #expect(decoder.decodePartiallyDownloadedData(Data([0xFF, 0xD8, 0xFF, 0xE0])) == nil)
        #expect(decoder.decodePartiallyDownloadedData(Data()) == nil)

        // Then
        #expect(decoder.decodePartiallyDownloadedData(data) != nil)
    }

    /// The pipeline doesn't call a decoder concurrently, but the decoder is
    /// `Sendable` and promises a single preview, so racing calls must agree
    /// on which one of them returns it.
    @Test func concurrentPartialDecodesProduceOnePreview() async throws {
        // Given
        let data = try await VideoFixture().makeData()
        let decoder = try #require(ImageDecoders.Video(context: .mock(data: data, isCompleted: false)))

        // When
        let previewCount = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask { decoder.decodePartiallyDownloadedData(data) != nil }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }

        // Then
        #expect(previewCount == 1)
    }
}

#endif
