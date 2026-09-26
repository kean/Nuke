// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

#if !os(macOS)
import UIKit
#else
import AppKit
import CoreImage
#endif

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)

@Suite(.timeLimit(.minutes(5)))
struct ImageProcessorsCoreImageFilterTests {
    @Test func applyFilterWithAnImageParameter() throws {
        // GIVEN a filter that takes a `CIImage` parameter
        let input = Test.image(named: "fixture-tiny.jpeg")
        let background = CIImage(cgImage: try #require(input.cgImage))
        let processor = ImageProcessors.CoreImageFilter(name: "CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: background], identifier: "composite")

        // WHEN
        let output = try #require(processor.process(input))

        // THEN
        #expect(output.sizeInPixels == input.sizeInPixels)
    }

    @Test func applyFilterWithInvalidName() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let processor = ImageProcessors.CoreImageFilter(name: "yo", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // THEN
        #expect(throws: ImageProcessors.CoreImageFilter.Error.self) {
            try processor.processThrowing(input)
        }
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func applyFilterToCIImage() throws {
        // GIVEN image backed by CIImage
        let input = PlatformImage(ciImage: CIImage(cgImage: Test.image.cgImage!))
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // WHEN
        let output = try #require(processor.process(input))

        // THEN the output is rendered at the size of the image backing the
        // input, which has no `CGImage` of its own to compare to
        #expect(output.sizeInPixels == Test.image.sizeInPixels)
    }
#endif

    @Test func applyFilterBackedByNothing() throws {
        // GIVEN empty image
        let input = PlatformImage()
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // THEN
        #expect(throws: ImageProcessors.CoreImageFilter.Error.self) {
            try processor.processThrowing(input)
        }
    }

    @Test func description() {
        // GIVEN
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.5], identifier: "CISepiaTone-75")

        // THEN
        #expect("\(processor)" == "CoreImageFilter(name: CISepiaTone, parameters: [\"inputIntensity\": 0.5])")
    }

    @Test func descriptionForCustomFilter() throws {
        // GIVEN
        let filter = try #require(CIFilter(name: "CISepiaTone", parameters: nil))
        let processor = ImageProcessors.CoreImageFilter(filter, identifier: "test")

        // THEN
        #expect("\(processor)".hasPrefix("CoreImageFilter(filter: "))
    }

    @Test func processingAnImageContainer() throws {
        // GIVEN
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone")
        let container = ImageContainer(image: Test.image(named: "fixture-tiny.jpeg"), data: Test.data)

        // WHEN
        let output = try processor.process(container, context: .mock)

        // THEN the image is replaced, and the data goes with it: it describes
        // the image that went in, not the one that came out
        #expect(output.image !== container.image)
        #expect(output.image.sizeInPixels == container.image.sizeInPixels)
        #expect(output.data == nil)
    }

    // MARK: - Context

    @Test func settingACustomContext() throws {
        // GIVEN
        let original = ImageProcessors.CoreImageFilter.context
        defer { ImageProcessors.CoreImageFilter.context = original }

        // WHEN
        ImageProcessors.CoreImageFilter.context = CIContext(options: [.useSoftwareRenderer: true])

        // THEN the filters keep working with the new context
        let processor = ImageProcessors.CoreImageFilter(name: "CISepiaTone")
        #expect(processor.process(Test.image(named: "fixture-tiny.jpeg")) != nil)
    }

    // MARK: - Errors

    @Test func filterProducingNoOutputImage() throws {
        // GIVEN a filter that can't produce an output without its second image
        let filter = try #require(CIFilter(name: "CISourceOverCompositing"))
        let processor = ImageProcessors.CoreImageFilter(filter, identifier: "test")

        // THEN
        #expect(throws: ImageProcessors.CoreImageFilter.Error.self) {
            try processor.processThrowing(Test.image(named: "fixture-tiny.jpeg"))
        }
    }

    @Test func filterProducingAnImageWithInfiniteExtent() throws {
        // GIVEN a filter whose output extent is infinite and can't be rendered
        let filter = try #require(CIFilter(name: "CIAffineClamp"))
        let processor = ImageProcessors.CoreImageFilter(filter, identifier: "test")

        // THEN
        #expect(throws: ImageProcessors.CoreImageFilter.Error.self) {
            try processor.processThrowing(Test.image(named: "fixture-tiny.jpeg"))
        }
    }

    @Test func errorDescriptions() throws {
        typealias Error = ImageProcessors.CoreImageFilter.Error

        #expect("\(Error.failedToCreateFilter(name: "CIYo", parameters: "[:]"))" == "Failed to create filter named CIYo with parameters: [:]")

        #expect("\(Error.inputImageIsEmpty(inputImage: "\(PlatformImage())"))".hasPrefix("Failed to create input CIImage for "))

        #expect("\(Error.failedToApplyFilter(name: "CISepiaTone"))" == "Failed to apply filter: CISepiaTone")

        let image = CIImage(cgImage: try #require(Test.image(named: "fixture-tiny.jpeg").cgImage))
        #expect("\(Error.failedToCreateOutputCGImage(extent: image.extent, image: "\(image)"))".hasPrefix("Failed to create output image for extent: "))
    }

    @Test func errorIsSendable() async throws {
        // GIVEN an error thrown by the processor
        let processor = ImageProcessors.CoreImageFilter(name: "yo", parameters: ["inputIntensity": 0.5], identifier: "yo")
        let thrown = #expect(throws: ImageProcessors.CoreImageFilter.Error.self) {
            try processor.processThrowing(Test.image(named: "fixture-tiny.jpeg"))
        }
        let error = try #require(thrown)

        // WHEN it crosses an isolation boundary, as it does wrapped in
        // `ImagePipeline.Error.processingFailed(processor:context:error:)`
        let description = await Task { @Sendable in error.description }.value

        // THEN
        #expect(description == "Failed to create filter named yo with parameters: [\"inputIntensity\": 0.5]")
    }

    @Test func applyCustomFilterDoesNotModifyTheGivenFilter() throws {
        // GIVEN
        let input = Test.image(named: "fixture-tiny.jpeg")
        let filter = try #require(CIFilter(name: "CISepiaTone", parameters: nil))
        let processor = ImageProcessors.CoreImageFilter(filter, identifier: "test")

        // WHEN
        _ = try #require(processor.process(input))

        // THEN the input image is never set on the filter owned by the client:
        // it is mutable and can't be shared by the requests running concurrently
        #expect(filter.value(forKey: kCIInputImageKey) == nil)
    }

    @Test func applyCustomFilterConcurrently() async throws {
        // GIVEN a single processor (and a single filter) shared by multiple
        // images, each with a distinct size
        let filter = try #require(CIFilter(name: "CISepiaTone", parameters: nil))
        let processor = ImageProcessors.CoreImageFilter(filter, identifier: "test")
        let widths = Array(20..<40)

        // WHEN processing them concurrently
        let outputs = await withTaskGroup(of: (Int, Int?).self) { group in
            for width in widths {
                group.addTask {
                    let input = Test.rgbImage(width: width, height: 10, color: CGColor(red: 0.5, green: 0.25, blue: 0.75, alpha: 1), alphaInfo: .premultipliedLast)
                    return (width, processor.process(input)?.cgImage?.width)
                }
            }
            var outputs = [Int: Int]()
            for await (width, output) in group {
                outputs[width] = output
            }
            return outputs
        }

        // THEN every image is processed and none of them is produced from the
        // input of another request
        for width in widths {
            #expect(outputs[width] == width)
        }
    }

    // MARK: - Identifiers

    @Test func identifiersAreDistinctForDifferentFilterNames() {
        // GIVEN two filters with different names (using the name-only initializer)
        let sepia = ImageProcessors.CoreImageFilter(name: "CISepiaTone")
        let bloom = ImageProcessors.CoreImageFilter(name: "CIBloom")

        // THEN their identifiers differ
        #expect(sepia.identifier != bloom.identifier)
    }

    @Test func identifiersAreEqualForSameFilterAndParameters() {
        // GIVEN two identically-configured filters
        let a = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.8], identifier: "sepia-80")
        let b = ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: ["inputIntensity": 0.8], identifier: "sepia-80")

        // THEN their identifiers are equal
        #expect(a.identifier == b.identifier)
    }

    @Test func identifierIsTheOneGivenByTheClient() throws {
        let filter = try #require(CIFilter(name: "CISepiaTone"))

        #expect(ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: [:], identifier: "sepia").identifier == "sepia")
        // `CoreImageFilter` isn't `Hashable`: the identifier is all there is
        #expect(ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: [:], identifier: "sepia").hashableIdentifier == AnyHashable("sepia"))
        #expect(ImageProcessors.CoreImageFilter(filter, identifier: "custom-sepia").identifier == "custom-sepia")
        #expect(ImageProcessors.CoreImageFilter(name: "CISepiaTone").identifier.contains("CISepiaTone"))
    }

    // MARK: - Output

    @Test func invalidFilterNameFailsTheBasicMethod() {
        // GIVEN
        let processor = ImageProcessors.CoreImageFilter(name: "CIDoesNotExist")

        // THEN the error is swallowed by the method that can't throw
        #expect(processor.process(Test.image(named: "fixture-tiny.jpeg")) == nil)
    }

    @Test func filterIsAppliedToThePixels() throws {
        // GIVEN a white image
        let input = Test.rgbImage(width: 10, height: 10, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))

        // WHEN
        let output = try #require(ImageProcessors.CoreImageFilter(name: "CIColorInvert").process(input))

        // THEN it is black
        #expect(output.sizeInPixels == CGSize(width: 10, height: 10))
        let pixel = try pixelComponents(of: output, x: 5, y: 5)
        #expect(pixel.prefix(3).allSatisfy { $0 <= 2 }, "\(pixel)")
    }

    @Test func parametersArePassedToTheFilter() throws {
        // GIVEN
        let input = Test.rgbImage(width: 10, height: 10, color: CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        let original = try pixelComponents(of: input, x: 5, y: 5)

        // WHEN
        let none = try #require(ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: [kCIInputIntensityKey: 0.0], identifier: "sepia-0").process(input))
        let full = try #require(ImageProcessors.CoreImageFilter(name: "CISepiaTone", parameters: [kCIInputIntensityKey: 1.0], identifier: "sepia-1").process(input))

        // THEN a sepia of zero intensity leaves the colors alone, and a full
        // one doesn't
        #expect(maxDifference(try pixelComponents(of: none, x: 5, y: 5), original) <= 4)
        #expect(maxDifference(try pixelComponents(of: full, x: 5, y: 5), original) > 16)
    }

    /// The processor applies a copy of the filter the client passes, and that
    /// copy has to carry the parameters the client set on the original.
    @Test func customFilterParametersSurviveTheCopy() throws {
        // GIVEN a filter configured by the client
        let input = Test.rgbImage(width: 10, height: 10, color: CGColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 1))
        let filter = try #require(CIFilter(name: "CISepiaTone"))
        filter.setValue(0.0, forKey: kCIInputIntensityKey)

        // WHEN
        let output = try #require(ImageProcessors.CoreImageFilter(filter, identifier: "sepia-0").process(input))

        // THEN
        #expect(maxDifference(try pixelComponents(of: output, x: 5, y: 5), try pixelComponents(of: input, x: 5, y: 5)) <= 4)
        #expect(filter.value(forKey: kCIInputIntensityKey) as? Double == 0)
    }

    @Test func staticApplyUsesTheGivenFilter() throws {
        // GIVEN
        let input = Test.rgbImage(width: 10, height: 10, color: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        let filter = try #require(CIFilter(name: "CIColorInvert"))

        // WHEN
        let output = try ImageProcessors.CoreImageFilter.apply(filter: filter, to: input)

        // THEN
        let pixel = try pixelComponents(of: output, x: 5, y: 5)
        #expect(pixel.prefix(3).allSatisfy { $0 <= 2 }, "\(pixel)")
        #expect(filter.value(forKey: kCIInputImageKey) == nil)
    }

#if os(iOS) || os(tvOS) || os(visionOS)
    @Test func filterPreservesScaleAndOrientation() throws {
        // GIVEN a @3x image rotated by the orientation
        let input = UIImage(cgImage: try #require(Test.image.cgImage), scale: 3, orientation: .right)

        // WHEN
        let output = try #require(ImageProcessors.CoreImageFilter(name: "CISepiaTone").process(input))

        // THEN
        #expect(output.scale == 3)
        #expect(output.imageOrientation == .right)
        #expect(output.size == input.size)
    }
#endif
}

private func maxDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
    zip(lhs.prefix(3), rhs.prefix(3)).map { abs(Int($0) - Int($1)) }.max() ?? 0
}

#endif
