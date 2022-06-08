# Nuke 11 Migration Guide

This guide eases the transition of the existing apps that use Nuke 10.x to the latest version of the framework.

> To learn about the new features in Nuke 11, see the [release notes](https://github.com/kean/Nuke/releases/tag/11.0.0).

## Minimum Requirements

- iOS 13.0, tvOS 13.0, macOS 10.15, watchOS 6.0
- Xcode 13.2
- Swift 5.5.2

## `ImageProcessing`

If you have custom image processors that implement `ImageProcessing` protocol using the method:

```swift
// Before (Nuke 10)
sturct CustomImageProcessor: ImageProcessing {
    func process(_ image: PlatformImage) -> PlatformImage? {
        image.drawInCircle()
    }
}
```

```swift
// After (Nuke 11)
sturct CustomImageProcessor: ImageProcessing {
    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        container.map { $0.drawInCircle() }
    }
}
```
