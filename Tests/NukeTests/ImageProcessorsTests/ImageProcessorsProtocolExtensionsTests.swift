// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation
import Testing

@testable import Nuke

@Suite struct ImageProcessorsProtocolExtensionsTests {

    @Test func passingProcessorsUsingProtocolExtensionsResize() throws {
        let size = CGSize(width: 100, height: 100)
        let processor = ImageProcessors.Resize(size: size)

        let request = try #require(ImageRequest(url: nil, processors: [.resize(size: size)]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

    @Test func passingProcessorsUsingProtocolExtensionsResizeWidthOnly() throws {
        let processor = ImageProcessors.Resize(width: 100)

        let request = try #require(ImageRequest(url: nil, processors: [.resize(width: 100)]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

    @Test func passingProcessorsUsingProtocolExtensionsResizeHeightOnly() throws {
        let processor = ImageProcessors.Resize(height: 100)

        let request = try #require(ImageRequest(url: nil, processors: [.resize(height: 100)]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

    @Test func passingProcessorsUsingProtocolExtensionsCircleEmpty() throws {
        let processor = ImageProcessors.Circle()

        let request = try #require(ImageRequest(url: nil, processors: [.circle()]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

    @Test func passingProcessorsUsingProtocolExtensionsCircle() throws {
        let border = ImageProcessingOptions.Border.init(color: .red)
        let processor = ImageProcessors.Circle(border: border)

        let request = try #require(ImageRequest(url: nil, processors: [.circle(border: border)]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

    @Test func passingProcessorsUsingProtocolExtensionsRoundedCorners() throws {
        let radius: CGFloat = 10
        let processor = ImageProcessors.RoundedCorners(radius: radius)

        let request = try #require(ImageRequest(url: nil, processors: [.roundedCorners(radius: radius)]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

    @Test func passingProcessorsUsingProtocolExtensionsAnonymous() throws {
        let id = UUID().uuidString
        let closure: (@Sendable (PlatformImage) -> PlatformImage?) = { _ in nil }
        let processor = ImageProcessors.Anonymous(id: id, closure)

        let request = try #require(ImageRequest(url: nil, processors: [.process(id: id, closure)]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
    @Test func passingProcessorsUsingProtocolExtensionsCoreImageFilterWithNameOnly() throws {
        let name = "CISepiaTone"
        let processor = ImageProcessors.CoreImageFilter(name: name)

        let request = try #require(ImageRequest(url: nil, processors: [.coreImageFilter(name: name)]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

    @Test func passingProcessorsUsingProtocolExtensionsCoreImageFilter() throws {
        let name = "CISepiaTone"
        let id = UUID().uuidString
        let processor = ImageProcessors.CoreImageFilter(name: name, parameters: [:], identifier: id)

        let request = try #require(ImageRequest(url: nil, processors: [.coreImageFilter(name: name, parameters: [:], identifier: id)]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

    @Test func passingProcessorsUsingProtocolExtensionsGaussianBlurEmpty() throws {
        let processor = ImageProcessors.GaussianBlur()

        let request = try #require(ImageRequest(url: nil, processors: [.gaussianBlur()]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }

    @Test func passingProcessorsUsingProtocolExtensionsGaussianBlur() throws {
        let radius = 10
        let processor = ImageProcessors.GaussianBlur(radius: radius)

        let request = try #require(ImageRequest(url: nil, processors: [.gaussianBlur(radius: radius)]))

        #expect(request.processors.first?.identifier == processor.identifier)
    }
#endif
}
