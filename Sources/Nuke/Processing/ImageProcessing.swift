// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Performs image processing.
///
/// For basic processing needs, implement the following method:
///
/// ```swift
/// func process(image: PlatformImage) -> PlatformImage?
/// ```
///
/// If your processor needs to manipulate image metadata (``ImageContainer``), or
/// get access to more information via the context (``ImageProcessingContext``),
/// there is an additional method that allows you to do that:
///
/// ```swift
/// func process(image container: ImageContainer, context: ImageProcessingContext) -> ImageContainer?
/// ```
///
/// You must implement either one of those methods.
public protocol ImageProcessing: Sendable {
    /// Returns a processed image. By default, returns `nil`.
    ///
    /// - note: Gets called a background queue managed by the pipeline.
    func process(_ image: PlatformImage) -> PlatformImage?

    /// Optional method. Returns a processed image. By default, this calls the
    /// basic `process(image:)` method.
    ///
    /// - note: Gets called a background queue managed by the pipeline.
    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer

    /// Returns a string that uniquely identifies the processor.
    ///
    /// Consider using the reverse DNS notation.
    var identifier: String { get }

    /// Returns a unique processor identifier.
    ///
    /// The default implementation simply returns `var identifier: String` but
    /// can be overridden as a performance optimization - creating and comparing
    /// strings is _expensive_ so you can opt-in to return something which is
    /// fast to create and to compare. See ``ImageProcessors/Resize`` for an example.
    ///
    /// - note: A common approach is to make your processor `Hashable` and return `self`
    /// as a hashable identifier.
    var hashableIdentifier: AnyHashable { get }
}

extension ImageProcessing {
    /// The default implementation simply calls the basic
    /// `process(_ image: PlatformImage) -> PlatformImage?` method.
    public func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        guard let output = process(container.image) else {
            throw ImageProcessingError.unknown
        }
        var container = container
        container.image = output
        return container
    }

    /// The default impleemntation simply returns `var identifier: String`.
    public var hashableIdentifier: AnyHashable { identifier }
}

extension ImageProcessing where Self: Hashable {
    public var hashableIdentifier: AnyHashable { self }
}

/// Image processing context used when selecting which processor to use.
public struct ImageProcessingContext: Sendable {
    public var request: ImageRequest
    public var response: ImageResponse
    public var isCompleted: Bool

    public init(request: ImageRequest, response: ImageResponse, isCompleted: Bool) {
        self.request = request
        self.response = response
        self.isCompleted = isCompleted
    }
}

public enum ImageProcessingError: Error, CustomStringConvertible, Sendable {
    case unknown

    public var description: String { "Unknown" }
}

func == (lhs: [any ImageProcessing], rhs: [any ImageProcessing]) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }
    // Lazily creates `hashableIdentifiers` because for some processors the
    // identifiers might be expensive to compute.
    return zip(lhs, rhs).allSatisfy {
        $0.hashableIdentifier == $1.hashableIdentifier
    }
}
