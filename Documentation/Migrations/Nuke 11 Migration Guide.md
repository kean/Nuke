# Nuke 11 Migration Guide

This guide eases the transition of the existing apps that use Nuke 10.x to the latest version of the framework.

> To learn about the new features in Nuke 11, see the [release notes](https://github.com/kean/Nuke/releases/tag/11.0.0).

## Minimum Requirements

- iOS 13.0, tvOS 13.0, macOS 10.15, watchOS 6.0
- Xcode 13.3
- Swift 5.6

## Error Reporting Improvements

If you are implementing custom image decoders or processors, their primary APIs are now throwing to allow the users to provide more information in case something goes wrong:

```swift
// Before (Nuke 10)
public protocol ImageDecoding {
    func decode(_ data: Data) -> ImageContainer?
}

// After (Nuke 11)
public protocol ImageDecoding {
    func decode(_ data: Data) throws -> ImageContainer
}
```

> You can use a new `ImageDecodingContext.unknown` in case there is nothing to report.

```swift
// Before (Nuke 10)
public protocol ImageProcessing {
    // This method has no changes.
    func process(_ image: PlatformImage) -> PlatformImage?

    func process(_ container: ImageContainer, context: ImageProcessingContext) -> ImageContainer?
}

// After (Nuke 11)
public protocol ImageProcessing {
    // This method has no changes.
    func process(_ image: PlatformImage) -> PlatformImage?

    // This is now throwing.
    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer
}
```

## ImageProcessing and Hashable

If you are implementing custom image processors `ImageProcessing` that implement `hashableIdentifier` and return self, you can remove the `hashableIdentifier` implementation and use the one provided by default.

```swift
// Before (Nuke 10)
extension ImageProcessors {
    /// Scales an image to a specified size.
    public struct Resize: ImageProcessing, Hashable {
        private let size: CGSize
        
        var hashableIdentiifer: AnyHashable { self }
    }
}

// After (Nuke 11)
extension ImageProcessors {
    /// Scales an image to a specified size.
    public struct Resize: ImageProcessing, Hashable {
        private let size: CGSize
    }
}
```

## Invalidation

If you invalidate the pipeline, any new requests will immediately fail with `ImagePipeline/Error/pipelineInvalidated` error.

## ImageRequestConvertible

`ImageRequestConvertible` was originally introduced in [Nuke 9.2](https://github.com/kean/Nuke/releases/tag/9.2.0) to reduce number of `loadImage(:)` APIs in code completion, but it's no longer an issue with the new async/await APIs.

`ImageRequestConvertible` is soft-deprecated in Nuke 11. The other soft-deprecated APIs, such as a closure-based `ImagePipeline/loadImage(:)` will continue working with it. The new APIs, such as async/await `ImagePipeline/image(for:)` will work with `URL` and `ImageRequest` which is better for discoverability and performance.

If you are using `ImageRequestConvertible` in your code, consider removing it now. But it won't be officially deprecated until the next major release.
