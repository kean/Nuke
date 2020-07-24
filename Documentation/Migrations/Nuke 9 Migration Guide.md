# Nuke 9 Migration Guide

This guide is provided in order to ease the transition of existing applications using Nuke 8.x to the latest version, as well as explain the design and structure of new and changed functionality.

> To learn about the new features in Nuke 9 see the [release notes](https://github.com/kean/Nuke/releases/tag/9.0.0).

## Minimum Requirements

- iOS 11.0, tvOS 11.0, macOS 10.13, watchOS 4.0
- Xcode 11.0
- Swift 5.1

## Overview

Nuke 9 contains a ton of new features, refinements, and performance improvements. There are some breaking changes and deprecated which the compiler is going to guide you through as you update.

## ImageProcessing

If you have custom image processors (`ImageProcessing` protocol), update `process(image:)` method to use the new signature. There are now two levels of image processing APIs: the basic and the advanced one. Please implement the one that best fits your needs.

```swift
// Nuke 8
func process(_ image: PlatformImage, context: ImageProcessingContext?) -> PlatformImage?

// Nuke 9
func process(_ image: UIImage) -> UIImage? // NSImage on macOS
// Optional
func process(_ image container: ImageContainer, context: ImageProcessingContext) -> ImageContainer?
```

## ImageDecoding

```swift
// Nuke 8
public protocol ImageDecoding {
    func decode(data: Data, isFinal: Bool) -> PlatformImage?
}

// Nuke 9
public protocol ImageDecoding {
    func decode(_ data: Data) -> ImageContainer?
    // Optional
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer?
}

public protocol ImageDecoderRegistering: ImageDecoding {
    init?(data: Data, context: ImageDecodingContext)
    // Optional
    init?(partiallyDownloadedData data: Data, context: ImageDecodingContext)
}
```

## ImageEncoding

If you have custom encoders (`ImageEncoding` protocol), update `encode(image:)` method to use the new signature. There are now two levels of image encoding APIs: the basic and the advanced one. Please implement the one that best fits your needs.

```swift
// Nuke 8
public protocol ImageEncoding {
    func encode(image: PlatformImage) -> Data?
}

// Nuke 9
public protocol ImageEncoding {
    func encode(_ image: PlatformImage) -> Data?
    // Optional
    func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data?
}
```

## ImageCaching

`ImageCaching` was updated to use `ImageContainer` type. Individual methods were replaced with a subscript.

```swift
// Nuke 8
public protocol ImageCaching: AnyObject {
    /// Returns the `ImageResponse` stored in the cache with the given request.
    func cachedResponse(for request: ImageRequest) -> ImageResponse?

    /// Stores the given `ImageResponse` in the cache using the given request.
    func storeResponse(_ response: ImageResponse, for request: ImageRequest)

    /// Remove the response for the given request.
    func removeResponse(for request: ImageRequest)
}

// Nuke 9
public protocol ImageCaching: AnyObject {
    subscript(request: ImageRequest) -> ImageContainer?
}
