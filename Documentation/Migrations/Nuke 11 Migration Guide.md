# Nuke 11 Migration Guide

This guide eases the transition of the existing apps that use Nuke 10.x to the latest version of the framework.

> To learn about the new features in Nuke 11, see the [release notes](https://github.com/kean/Nuke/releases/tag/11.0.0).

## Minimum Requirements

- iOS 13.0, tvOS 13.0, macOS 10.15, watchOS 6.0
- Xcode 13.2
- Swift 5.5.2


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
