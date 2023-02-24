# Nuke 12 Migration Guide

This guide eases the transition of the existing apps that use Nuke 11.x to the latest version of the framework.

> To learn about the new features in Nuke 12, see the [release notes](https://github.com/kean/Nuke/releases/tag/12.0.0).

## Minimum Requirements

The minimum requirements are unchanged.

- iOS 13.0, tvOS 13.0, macOS 10.15, watchOS 6.0
- Xcode 13.3
- Swift 5.6

## Async/Await

The existing convenience `ImagePipeline/image(for:)` methods now return an image (`UIImage` or `NSImage`)  instead of `ImageResponse`.

```swift
// Before (Nuke 11)
let image: ImageResponse = try await ImagePipeline.shared.image(for: url)

// After (Nuke 12)
let image: UIImage = try await ImagePipeline.shared.image(for: url)

// To retrieve an `ImageResponse` use a new `imageTask(with:)` method (Nuke 12)
let response = try await ImagePipeline.shared.imageTask(with: url).response
```

The existing `ImagePipeline/image(for:)` method also no longer has an `ImageTaskDelegate` parameter – there was no way to make it `Sendable` without compromises. Instead, use the new `ImagePipeline.imageTask(with:)` method that returns an instance of a new `AsyncImageTask` type.

```swift
// Before (Nuke 11)
let response = try await ImagePipeline.shared.image(for: url, delegate: self)

func imageTaskCreated(_ task: ImageTask) {
    self.imageTask = task
}

func imageTask(_ task: ImageTask, didReceivePreview response: ImageResponse) {
    // Gets called for images that support progressive decoding.
}

func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress) {
    // Gets called when the download progress is updated.
}
```

```swift
// After (Nuke 12)
let imageTask = ImagePipeline.shared.imageTask(with: url)
for await progress in imageTask.progress {
    // Update progress
}
imageView.image = try await imageTask.image
```

The new API is both easier to use, _and_ it's fully `Sendable` compliant.
