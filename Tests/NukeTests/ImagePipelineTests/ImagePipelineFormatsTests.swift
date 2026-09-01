// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineFormatsTests {
    let dataLoader: MockDataLoader
    let pipeline: ImagePipeline

    init() {
        let dataLoader = MockDataLoader()
        self.dataLoader = dataLoader
        self.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    @Test func extendedColorSpaceSupport() async throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "image-p3", extension: "jpg"), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        let image = response.image
        let cgImage = try #require(image.cgImage)
        let colorSpace = try #require(cgImage.colorSpace)
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
        #expect(colorSpace.isWideGamutRGB)
#elseif os(watchOS)
        #expect(!colorSpace.isWideGamutRGB)
#endif
    }

    @Test func grayscaleSupport() async throws {
        // Given
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "grayscale", extension: "jpeg"), URLResponse(url: Test.url, mimeType: "jpeg", expectedContentLength: 20, textEncodingName: nil))
        )

        // When
        let response = try await pipeline.imageTask(with: Test.request).response

        // Then
        let image = response.image
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.bitsPerComponent == 8)
    }

    // MARK: - Image Formats

    @Test func loadPNG() async throws {
        // GIVEN a pipeline that returns PNG data
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "fixture", extension: "png"),
             URLResponse(url: Test.url, mimeType: "png", expectedContentLength: 0, textEncodingName: nil))
        )

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN the image is decoded correctly
        #expect(response.container.type == .png)
        #expect(response.image.sizeInPixels == CGSize(width: 640, height: 360))
    }

    @Test func loadGIF() async throws {
        // GIVEN a pipeline that returns GIF data
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "cat", extension: "gif"),
             URLResponse(url: Test.url, mimeType: "gif", expectedContentLength: 0, textEncodingName: nil))
        )

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN GIF data is preserved in the container for animated playback
        #expect(response.container.type == .gif)
        #expect(response.container.data != nil)
        #expect(response.container.animation != nil)
    }

    // MARK: - Animations

    @Test func animationIsParsedOnceAndTravelsWithTheImage() async throws {
        // GIVEN a pipeline with a memory cache, which is what a list scrolled
        // back to an animation reads from
        let pipeline = pipeline.reconfigured { $0.imageCache = ImageCache() }
        serveAnimatedGIF(frameCount: 7)

        // WHEN the same image is loaded twice
        let first = try await pipeline.imageTask(with: Test.request).response
        let second = try await pipeline.imageTask(with: Test.request).response

        // THEN the animation is parsed once and handed out as it is. Its
        // lifetime is the memory cache entry's, which is what makes a cache of
        // parses – with a bound of its own, holding on to encoded data the
        // image cache has already evicted – unnecessary.
        #expect(first.container.animation?.frameCount == 7)
        #expect(first.container.animation === second.container.animation)
    }

    @Test func animationParsingCanBeTurnedOff() async throws {
        // GIVEN a pipeline told not to parse animations
        let pipeline = pipeline.reconfigured { $0.isAnimatedImageParsingEnabled = false }
        serveAnimatedGIF(frameCount: 7)

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN the data still travels, so a renderer that parses it itself is
        // unaffected
        #expect(response.container.data != nil)
        #expect(response.container.animation == nil)
    }

    private func serveAnimatedGIF(frameCount: Int) {
        dataLoader.results[Test.url] = .success(
            (Test.animatedGIF(frameCount: frameCount),
             URLResponse(url: Test.url, mimeType: "gif", expectedContentLength: 0, textEncodingName: nil))
        )
    }

    @Test func loadHEIC() async throws {
        // GIVEN a pipeline that returns HEIC data
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "img_751", extension: "heic"),
             URLResponse(url: Test.url, mimeType: "heic", expectedContentLength: 0, textEncodingName: nil))
        )

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN image is decoded correctly
        #expect(response.container.type == .heic)
        #expect(response.image.sizeInPixels != .zero)
    }

#if os(iOS) || os(macOS) || os(visionOS)
    @Test func loadWebP() async throws {
        // GIVEN a pipeline that returns WebP data
        dataLoader.results[Test.url] = .success(
            (Test.data(name: "baseline", extension: "webp"),
             URLResponse(url: Test.url, mimeType: "webp", expectedContentLength: 0, textEncodingName: nil))
        )

        // WHEN
        let response = try await pipeline.imageTask(with: Test.request).response

        // THEN image is decoded correctly
        #expect(response.container.type == .webp)
        #expect(response.image.sizeInPixels == CGSize(width: 550, height: 368))
    }
#endif
}
