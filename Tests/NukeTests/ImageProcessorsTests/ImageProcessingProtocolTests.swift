// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

#if !os(macOS)
import UIKit
#else
import AppKit
#endif

/// The contract of ``ImageProcessing`` itself: the default implementations
/// every processor inherits, and the identifiers the caches are keyed on.
@Suite(.timeLimit(.minutes(5)))
struct ImageProcessingProtocolTests {

    // MARK: - Hashable Identifier

    @Test func defaultHashableIdentifierIsTheIdentifier() {
        // Given a processor that isn't `Hashable`
        let processor = StringIdentifiedProcessor(identifier: "com.example/plain")

        // Then
        #expect(processor.hashableIdentifier == AnyHashable("com.example/plain"))
    }

    @Test func hashableProcessorUsesItselfAsHashableIdentifier() {
        // Given two `Hashable` processors that report the same string identifier
        let lhs = HashableProcessor(value: 1)
        let rhs = HashableProcessor(value: 2)
        #expect(lhs.identifier == rhs.identifier)

        // Then the memory cache still tells them apart: the hashable identifier
        // is the processor itself, not its string identifier
        #expect(lhs.hashableIdentifier == AnyHashable(lhs))
        #expect(lhs.hashableIdentifier != rhs.hashableIdentifier)
        #expect(lhs.hashableIdentifier == HashableProcessor(value: 1).hashableIdentifier)
    }

    /// The built-in `Hashable` processors are compared as values in the memory
    /// cache, so a custom processor that happens to reuse one of their string
    /// identifiers can't be served their output from it. The disk cache is
    /// keyed on the string identifier alone.
    @Test func builtInProcessorsAreNotConfusedWithCustomOnesSharingTheirIdentifier() {
        let circle = ImageProcessors.Circle()
        let impostor = ImageProcessors.Anonymous(id: circle.identifier) { $0 }

        #expect(circle.identifier == impostor.identifier)
        #expect(circle.hashableIdentifier != impostor.hashableIdentifier)
    }

    // MARK: - Default Container Processing

    /// The data and the animation describe the image that went in: a renderer
    /// handed both would play the original over the processed still.
    @Test func defaultContainerProcessingDropsDataAndAnimationButKeepsTheRest() throws {
        // Given an animated container
        let data = Test.animatedGIF()
        let animation = try #require(AnimatedImageSource(data: data))
        let container = ImageContainer(
            image: Test.image,
            type: .gif,
            isPreview: true,
            data: data,
            animation: animation,
            userInfo: ["key": "value"]
        )

        // When
        let output = try MockImageProcessor(id: "1").process(container, context: .mock)

        // Then
        #expect(output.image.nk_test_processorIDs == ["1"])
        #expect(output.data == nil)
        #expect(output.animation == nil)
        #expect(output.type == .gif)
        #expect(output.isPreview)
        #expect(output.userInfo["key"] as? String == "value")

        // Then the input is left untouched
        #expect(container.data == data)
        #expect(container.animation != nil)
    }

    @Test func defaultContainerProcessingThrowsWhenTheBasicMethodFails() {
        // Given
        let processor = MockFailingProcessor()

        // Then
        #expect(throws: ImageProcessingError.self) {
            try processor.process(Test.container, context: .mock)
        }
    }

    // MARK: - Context and Errors

    @Test func processingContextStoresTheGivenValues() {
        // Given
        let request = ImageRequest(url: URL(string: "https://example.com/image.png"))
        let response = ImageResponse(container: Test.container, request: request)

        // When
        let context = ImageProcessingContext(request: request, response: response, isCompleted: false)

        // Then
        #expect(context.request.url == request.url)
        #expect(context.response.image === response.image)
        #expect(!context.isCompleted)
    }

    @Test func processingErrorDescription() {
        #expect(ImageProcessingError.unknown.description == "Unknown")
        #expect("\(ImageProcessingError.unknown)" == "Unknown")
    }
}

// MARK: - Identifier Uniqueness

/// The disk cache is keyed on ``ImageProcessing/identifier`` and the memory
/// cache on ``ImageProcessing/hashableIdentifier``. Two configurations that
/// produce different images but share either one would serve the output of one
/// to the requests of the other.
@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorIdentifierUniquenessTests {

    /// Every configuration here can produce a different image. Some of them
    /// match for some inputs – `upscale` makes no difference when downscaling,
    /// `crop` none with `.aspectFit` – but they are still keyed separately.
    static let configurations: [(label: String, make: @Sendable () -> any ImageProcessing)] = {
        var configurations: [(String, @Sendable () -> any ImageProcessing)] = []
        for size in [CGSize(width: 30, height: 30), CGSize(width: 30, height: 40), CGSize(width: 40, height: 30)] {
            for contentMode in [ImageProcessingOptions.ContentMode.aspectFill, .aspectFit] {
                for crop in [false, true] {
                    for upscale in [false, true] {
                        configurations.append(("resize(\(size), \(contentMode), crop: \(crop), upscale: \(upscale))", {
                            ImageProcessors.Resize(size: size, unit: .pixels, contentMode: contentMode, crop: crop, upscale: upscale)
                        }))
                    }
                }
            }
        }
        for upscale in [false, true] {
            configurations.append(("resize(width: 30, upscale: \(upscale))", { ImageProcessors.Resize(width: 30, unit: .pixels, upscale: upscale) }))
            configurations.append(("resize(height: 30, upscale: \(upscale))", { ImageProcessors.Resize(height: 30, unit: .pixels, upscale: upscale) }))
        }
        let others: [(String, @Sendable () -> any ImageProcessing)] = [
            ("circle", { ImageProcessors.Circle() }),
            ("circle(red, 2)", { ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)) }),
            ("circle(red, 4)", { ImageProcessors.Circle(border: .init(color: .red, width: 4, unit: .pixels)) }),
            ("circle(blue, 2)", { ImageProcessors.Circle(border: .init(color: .blue, width: 2, unit: .pixels)) }),
            ("circle(red 50%, 2)", { ImageProcessors.Circle(border: .init(color: PlatformColor.red.withAlphaComponent(0.5), width: 2, unit: .pixels)) }),
            ("roundedCorners(8)", { ImageProcessors.RoundedCorners(radius: 8, unit: .pixels) }),
            ("roundedCorners(16)", { ImageProcessors.RoundedCorners(radius: 16, unit: .pixels) }),
            ("roundedCorners(8, red 2)", { ImageProcessors.RoundedCorners(radius: 8, unit: .pixels, border: .init(color: .red, width: 2, unit: .pixels)) }),
            ("roundedCorners(8, red 4)", { ImageProcessors.RoundedCorners(radius: 8, unit: .pixels, border: .init(color: .red, width: 4, unit: .pixels)) }),
            ("roundedCorners(8, blue 2)", { ImageProcessors.RoundedCorners(radius: 8, unit: .pixels, border: .init(color: .blue, width: 2, unit: .pixels)) }),
            ("anonymous(a)", { ImageProcessors.Anonymous(id: "a") { $0 } }),
            ("anonymous(b)", { ImageProcessors.Anonymous(id: "b") { $0 } }),
            ("composition([])", { ImageProcessors.Composition([]) }),
            ("composition([circle, blur])", { ImageProcessors.Composition([ImageProcessors.Circle(), ImageProcessors.Anonymous(id: "blur") { $0 }]) }),
            ("composition([blur, circle])", { ImageProcessors.Composition([ImageProcessors.Anonymous(id: "blur") { $0 }, ImageProcessors.Circle()]) })
        ]
        configurations += others
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
        for radius in [0, 1, 2, 8] {
            configurations.append(("gaussianBlur(\(radius))", { ImageProcessors.GaussianBlur(radius: radius) }))
        }
        let filters: [(String, @Sendable () -> any ImageProcessing)] = [
            ("coreImage(CISepiaTone)", { ImageProcessors.CoreImageFilter(name: "CISepiaTone") }),
            ("coreImage(CIColorInvert)", { ImageProcessors.CoreImageFilter(name: "CIColorInvert") })
        ]
        configurations += filters
#endif
        return configurations
    }()

    @Test func differentConfigurationsNeverShareIdentifiers() {
        let processors = Self.configurations.map { ($0.label, $0.make()) }
        for i in processors.indices {
            for j in processors.indices where j > i {
                let (lhsLabel, lhs) = processors[i]
                let (rhsLabel, rhs) = processors[j]
                #expect(lhs.identifier != rhs.identifier, "\(lhsLabel) vs \(rhsLabel)")
                #expect(lhs.hashableIdentifier != rhs.hashableIdentifier, "\(lhsLabel) vs \(rhsLabel)")
            }
        }
    }

    @Test func sameConfigurationAlwaysProducesTheSameIdentifiers() {
        for (label, make) in Self.configurations {
            let lhs = make()
            let rhs = make()
            #expect(lhs.identifier == rhs.identifier, "\(label)")
            #expect(lhs.hashableIdentifier == rhs.hashableIdentifier, "\(label)")
            #expect(lhs.hashableIdentifier.hashValue == rhs.hashableIdentifier.hashValue, "\(label)")
        }
    }

    @Test func dataCacheKeysAreDistinctForEveryConfiguration() {
        // Given
        let pipeline = ImagePipeline { $0.dataLoader = MockDataLoader() }

        // When
        let keys = Self.configurations.map {
            pipeline.cache.makeDataCacheKey(for: ImageRequest(url: Test.url, processors: [$0.make()]))
        }

        // Then
        #expect(Set(keys).count == keys.count)
    }
}

// MARK: - Formats

/// The identifiers and descriptions of the built-in processors, character for
/// character. An identifier is part of the disk cache key: any change to its
/// format orphans every processed image that is already on disk.
///
/// ``ImageProcessors/Resize`` is pinned row by row, crop included, by
/// `ImageProcessorsResizeTests.identifierFormat`. The values in points are
/// pinned by the `pointsAndPixelsProduceTheSameIdentifiers` test of every
/// processor that takes them: they produce the identifiers of the same values
/// in pixels.
@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorFormatTests {
    @Test(arguments: identifierFormats)
    func identifierFormatsArePinned(processor: any ImageProcessing, identifier: String) {
        #expect(processor.identifier == identifier)
    }

    /// The descriptions that the tests of the processors don't already pin.
    @Test(arguments: descriptionFormats)
    func descriptionFormatsArePinned(processor: any ImageProcessing & CustomStringConvertible, description: String) {
        #expect(processor.description == description)
    }
}

private let identifierFormats: [(any ImageProcessing, String)] = {
    var formats: [(any ImageProcessing, String)] = [
        (ImageProcessors.RoundedCorners(radius: 16, unit: .pixels), "com.github.kean/nuke/rounded_corners?radius=16.0"),
        (ImageProcessors.RoundedCorners(radius: 16, unit: .pixels, border: .init(color: .red, width: 2, unit: .pixels)), "com.github.kean/nuke/rounded_corners?radius=16.0,border=Border(color: #FF0000, width: 2.0 pixels)"),
        (ImageProcessors.Circle(), "com.github.kean/nuke/circle"),
        (ImageProcessors.Circle(border: .init(color: .red, width: 2, unit: .pixels)), "com.github.kean/nuke/circle?border=Border(color: #FF0000, width: 2.0 pixels)"),
        (ImageProcessors.Anonymous(id: "com.example/invert") { $0 }, "com.example/invert"),
        // The identifiers of the processors, concatenated
        (ImageProcessors.Composition([]), ""),
        (ImageProcessors.Composition([ImageProcessors.Circle(), ImageProcessors.RoundedCorners(radius: 8, unit: .pixels)]), "com.github.kean/nuke/circlecom.github.kean/nuke/rounded_corners?radius=8.0")
    ]
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    formats += [
        (ImageProcessors.GaussianBlur(), "com.github.kean/nuke/gaussian_blur?radius=8"),
        // The `)` with no opening one is in every key this initializer has
        // produced, so it stays
        (ImageProcessors.CoreImageFilter(name: "CISepiaTone"), "com.github.kean/nuke/core_image?name=CISepiaTone)"),
        (ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "com.example/sepia"), "com.example/sepia")
    ]
#endif
    return formats
}()

private let descriptionFormats: [(any ImageProcessing & CustomStringConvertible, String)] = {
    var formats: [(any ImageProcessing & CustomStringConvertible, String)] = [
        (ImageProcessors.Anonymous(id: "com.example/invert") { $0 }, "AnonymousProcessor(identifier: com.example/invert)")
    ]
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    formats += [
        (ImageProcessors.GaussianBlur(), "GaussianBlur(radius: 8)")
    ]
#endif
    return formats
}()

// MARK: - Helpers

private struct StringIdentifiedProcessor: ImageProcessing {
    let identifier: String

    func process(_ image: PlatformImage) -> PlatformImage? { image }
}

private struct HashableProcessor: ImageProcessing, Hashable {
    let value: Int

    var identifier: String { "com.example/hashable" }

    func process(_ image: PlatformImage) -> PlatformImage? { image }
}
