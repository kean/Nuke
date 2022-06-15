// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

#if os(iOS) || os(tvOS) || os(macOS)

import Foundation
import CoreImage

extension ImageProcessors {

    /// Applies Core Image filter (`CIFilter`) to the image.
    ///
    /// # Performance Considerations.
    ///
    /// Prefer chaining multiple `CIFilter` objects using `Core Image` facilities
    /// instead of using multiple instances of `ImageProcessors.CoreImageFilter`.
    ///
    /// # References
    ///
    /// - [Core Image Programming Guide](https://developer.apple.com/library/ios/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_intro/ci_intro.html)
    /// - [Core Image Filter Reference](https://developer.apple.com/library/prerelease/ios/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html)
    public struct CoreImageFilter: ImageProcessing, CustomStringConvertible, @unchecked Sendable {
        public let name: String
        public let parameters: [String: Any]
        public let identifier: String

        /// - parameter identifier: Uniquely identifies the processor.
        public init(name: String, parameters: [String: Any], identifier: String) {
            self.name = name
            self.parameters = parameters
            self.identifier = identifier
        }

        public init(name: String) {
            self.name = name
            self.parameters = [:]
            self.identifier = "com.github.kean/nuke/core_image?name=\(name))"
        }

        public func process(_ image: PlatformImage) -> PlatformImage? {
            try? _process(image)
        }

        public func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
            try container.map(_process(_:))
        }

        private func _process(_ image: PlatformImage) throws -> PlatformImage {
            try CoreImageFilter.applyFilter(named: name, parameters: parameters, to: image)
        }

        // MARK: - Apply Filter

        /// A default context shared between all Core Image filters. The context
        /// has `.priorityRequestLow` option set to `true`.
        public static var context = CIContext(options: [.priorityRequestLow: true])

        static func applyFilter(named name: String, parameters: [String: Any] = [:], to image: PlatformImage) throws -> PlatformImage {
            guard let filter = CIFilter(name: name, parameters: parameters) else {
                throw Error.failedToCreateFilter(name: name, parameters: parameters)
            }
            return try CoreImageFilter.apply(filter: filter, to: image)
        }

        /// Applies filter to the given image.
        public static func apply(filter: CIFilter, to image: PlatformImage) throws -> PlatformImage {
            func getCIImage() throws -> CoreImage.CIImage {
                if let image = image.ciImage {
                    return image
                }
                if let image = image.cgImage {
                    return CoreImage.CIImage(cgImage: image)
                }
                throw Error.inputImageIsEmpty(inputImage: image)
            }
            filter.setValue(try getCIImage(), forKey: kCIInputImageKey)
            guard let outputImage = filter.outputImage else {
                throw Error.failedToApplyFilter(filter: filter)
            }
            guard let imageRef = context.createCGImage(outputImage, from: outputImage.extent) else {
                throw Error.failedToCreateOutputCGImage(image: outputImage)
            }
            return PlatformImage.make(cgImage: imageRef, source: image)
        }

        public var description: String {
            "CoreImageFilter(name: \(name), parameters: \(parameters))"
        }

        public enum Error: Swift.Error, CustomStringConvertible {
            case failedToCreateFilter(name: String, parameters: [String: Any])
            case inputImageIsEmpty(inputImage: PlatformImage)
            case failedToApplyFilter(filter: CIFilter)
            case failedToCreateOutputCGImage(image: CIImage)

            public var description: String {
                switch self {
                case let .failedToCreateFilter(name, parameters):
                    return "Failed to create filter named \(name) with parameters: \(parameters)"
                case let .inputImageIsEmpty(inputImage):
                    return "Failed to create input CIImage for \(inputImage)"
                case let .failedToApplyFilter(filter):
                    return "Failed to apply filter: \(filter.name)"
                case let .failedToCreateOutputCGImage(image):
                    return "Failed to create output image for extent: \(image.extent) from \(image)"
                }
            }
        }
    }
}

#endif
