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

// To retrieve `ImageResponse` use new `imageTask(with:)` method (Nuke 12)
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

If you implement `ImageTaskDelegate` as part of the pipeline's delegate, make sure to update the method to include the new `pipeline` parameter:

```swift
// Before (Nuke 11)
final class YourPipelineDelegate: ImagePipelineDelegate {
    func imageTaskCreated(_ task: ImageTask) {
        // ...
    }
}

// After (Nuke 12)
final class YourPipelineDelegate: ImagePipelineDelegate {
    func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
        // ...
    }
}
```

## LazyImage

In addition to the changes to the `LazyImage` interface, there are a couple of important internal changes:

- It now uses `SwiftUI.Image` for displayed fetched images, which changes its self-sizing and layout behavior that now exactly matches `AsyncImage`
- It no longer plays GIFs and videos
- Transition animations are disabled by default
- Progress updates no longer trigger `content` reload

So it's best to think about it as an entirely new component, rather than an improvement of the previous one. This is one of the major reasons that instead of API deprecations, this release straight-up changes the existing APIs.

To achieve the previous sizing behavior, you'll now need to provide a `content` closure – just like with `AsyncImage`. It's slightly more code, but it provides you complete access to the underlying image.

```swift
// Before (Nuke 11)
LazyImage(url: URL(string: "https://example.com/image.jpeg"), resizingMode: .aspectFill) 

// After (Nuke 12)
LazyImage(url: URL(string: "https://example.com/image.jpeg")) { state in
    if let image = state.image {
        image
            .resizable()
            .aspectRatio(contentMode: .fill)
    }
}
```

To display animated image, use one of the GIF rendering frameworks, such as [Gifu](https://github.com/kaishin/Gifu), directly:

```swift
// After (Nuke 12)
LazyImage(url: URL(string: "https://example.com/image.jpeg")) { state in
    if let container = state.imageContainer {
        if container.type == .gif {
            // Use a view capable of displaying animated images
        } else {
            state.image // Use the default view
        }
    }
}
```

The same approach applies to videos, but you can use the built-in `NukeVideo` module to render them.

The way you enable animations have also been updated and matches `AsyncImage`:

```swift
// Before (Nuke 11)
LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    .animation(.default)
    
// After (Nuke 12)
LazyImage(url: URL(string: "https://example.com/image.jpeg"),
          transaction: .init(animation: .default)) {
    $0.image
}
```

And progress updates are no longer bundled with the rest of the state updates, which significantly reduces the number of `LazyImage` `content` reloads.

```swift
// Before (Nuke 11)
LazyImage(url: URL(string: "https://example.com/image.jpeg")) { state in 
    if state.isLoading {
        Text("\(state.progress.fraction * 100) %")
    }
}
    
// After (Nuke 12)
LazyImage(url: URL(string: "https://example.com/image.jpeg")) { state in
    if state.isLoading {
        ProgressView(state.progress)
    }
}

struct ProgressView: View {
    @ObservedObject var progress: FetchImage.Progress

    var body: some View {
        Text("progress.fraction * 100 %")
    }
}
```

## NukeVideo

To enable video support, you'll now need to import the new `NukeVideo` framework to your project and register the video decoder.

```swift
ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
```

Here is an example of playing the video using `LazyImageView` (NukeUI) and `VideoPlayerView` (NukeVideo):

```swift
let imageView = LazyImageView()
imageView.makeImageView = { container in
    if let type = container.type, type.isVideo, let asset = container.userInfo[.videoAssetKey] as? AVAsset {
        let view = VideoPlayerView()
        view.asset = asset
        view.play()
        return view
    }
    return nil
}

imageView.url = /* video URL */
```
