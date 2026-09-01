# Nuke 14 Migration Guide

This guide eases the transition of the existing apps that use Nuke 13.x to the latest version of the framework.

> Nuke 14 is a work in progress. The guide is updated as the changes land.

## Minimum Requirements

The minimum supported platforms have been raised.

- iOS 16.0, tvOS 16.0, macOS 13.0, watchOS 9.0, visionOS 1.0
- Xcode 26.0
- Swift 6.2

Apps that need to support earlier OS versions can stay on Nuke 13.x, which continues to receive fixes.

## `NukeExtensions` Folded into `NukeUI`

The image view extensions – `loadImage(with:into:)`, `cancelRequest(for:)`, `ImageLoadingOptions`, and the display protocol – moved from `NukeExtensions` to `NukeUI`, which is where the other UIKit and AppKit views already lived. The package now ships three modules: `Nuke`, `NukeUI`, and `NukeVideo`.

`NukeExtensions` still exists as an empty module that re-exports `NukeUI`, so existing code keeps compiling. It will be removed in Nuke 15.

```swift
// Before
import NukeExtensions

// After
import NukeUI
```

If you referenced the functions by module name, update the prefix:

```swift
// Before
NukeExtensions.loadImage(with: url, into: imageView)

// After
NukeUI.loadImage(with: url, into: imageView)
```

## `Nuke_ImageDisplaying` is now `ImageDisplaying`

The protocol lost its `@objc`, its prefix, and its two-argument method. It now takes the whole `ImageContainer`, which is where the animated images the pipeline parses live:

```swift
// Nuke 13
extension MyImageView: Nuke_ImageDisplaying {
    func nuke_display(image: UIImage?, data: Data?) {
        self.image = image
    }
}

// Nuke 14
extension MyImageView: ImageDisplaying {
    func nuke_display(_ container: ImageContainer?) {
        self.image = container?.image
    }
}
```

`image` and `data` are `container?.image` and `container?.data`, and `nil` is the "clear the view" call that used to be `nuke_display(image: nil, data: nil)`. A view that rendered animations from the data now has `container?.animation` as well, already parsed – see below.

The method keeps its `nuke_` prefix because the built-in conformances ship as extensions of system classes. `ImageDisplayingView` is unchanged.

What does not survive is **overriding the display method in a `UIImageView` subclass**. Swift resolves a protocol requirement witnessed in an extension statically, so the subclass's method is never called:

```swift
// Nuke 13 – no longer works
final class MyImageView: UIImageView {
    override func nuke_display(image: UIImage?, data: Data?) { ... }
}
```

Declare the conformance on your own class instead:

```swift
// Nuke 14
final class MyImageView: UIView, ImageDisplaying {
    private let imageView = UIImageView()

    func nuke_display(_ container: ImageContainer?) {
        imageView.image = container?.image
    }
}
```

If the subclass existed to play animated images, `AnimatedImageView` does it already.

## The Pipeline Parses Animated Images

`ImageDecoders.Default` already attached the encoded bytes of an animated image to `ImageContainer.data`. It now also parses them and attaches the result to the new `ImageContainer.animation`.

```swift
// Nuke 13
guard let source = AnimatedImageSource(data: response.container.data ?? Data()) else { return }

// Nuke 14
guard let animation = response.container.animation else { return }
```

`AnimatedImageSource` moved from `NukeUI` to `Nuke`. `NukeUI` re-exports `Nuke`, so code that imports either keeps compiling.

The parse runs on the decoding queue, once per decoded image, and the result is cached with the container. `container.data != nil` is a header sniff and is `true` for a single-frame GIF; `container.animation != nil` is the parsed answer, so prefer it when the question is "can this be played?".

The parse walks the metadata of every frame and is paid whether or not the image is ever displayed. Turn it off in an app that plays animations some other way, or none at all:

```swift
ImagePipeline.shared = ImagePipeline {
    $0.isAnimatedImageParsingEnabled = false
}
```

`ImageContainer.data` is unaffected by the flag, so a renderer that parses the data itself keeps working. Processing an image now clears both `data` and `animation`, which describe the image that went into the processor.

## Removed Deprecated APIs

The APIs deprecated in Nuke 13 have been removed.

| Removed | Replacement |
|---|---|
| `ImagePipelineDelegate` | `ImagePipeline.Delegate` |
| `ImageRequest.imageId` | `ImageRequest.imageID` |
| `ImageRequest.UserInfoKey.imageIdKey` | `ImageRequest.imageID` |
| `ImageRequest.UserInfoKey.scaleKey` | `ImageRequest.scale` |
| `ImageRequest.UserInfoKey.thumbnailKey` | `ImageRequest.thumbnail` |
| `ImagePipeline.Configuration.maximumDecodedImageSize` | `ImageRequest.ThumbnailOptions` |
| `ImageDecodingContext.maximumDecodedImageSize` | `ImageRequest.ThumbnailOptions` |

The automatic downscaling implementation behind `maximumDecodedImageSize` was removed in Nuke 13, so setting it already had no effect. Use `ImageRequest.ThumbnailOptions` to control the decoded image size on a per-request basis instead.

## Removed `userInfo` from `ImageRequest` Initializers

The `userInfo` parameter, soft-deprecated in Nuke 13, is gone from the `ImageRequest` initializers. The options it used to carry now have dedicated type-safe properties, and `userInfo` itself remains available as a property for custom values.

```swift
// Before
let request = ImageRequest(url: url, userInfo: ["key": "value"])

// After
var request = ImageRequest(url: url)
request.userInfo = ["key": "value"]
```

## Removed Combine Support

The Combine APIs are gone. Use the Async/Await APIs instead.

| Removed | Replacement |
|---|---|
| `ImagePipeline.imagePublisher(with:)` | `ImagePipeline.image(for:)` or `ImagePipeline.imageTask(with:)` |
| `FetchImage.load(_:)` taking a `Publisher` | `FetchImage.load(_:)` taking an async closure |

```swift
// Nuke 13
cancellable = ImagePipeline.shared.imagePublisher(with: url)
    .sink(receiveCompletion: { _ in }, receiveValue: { response in
        imageView.image = response.image
    })

// Nuke 14
imageView.image = try await ImagePipeline.shared.image(for: url)
```

To observe progressively decoded previews, which the publisher used to emit as intermediate values, use `ImageTask.previews`.

`FetchImage` remains an `ObservableObject`, so observing it from SwiftUI is unchanged.

## Removed `ImageTask.Event.started`

`ImageTask.Event.started` is gone. It was never delivered to `ImageTask.events` – the pipeline reported it to the delegate directly – so it only ever existed for `ImagePipeline.Delegate`. The delegate now has a dedicated method instead.

```swift
// Nuke 13
func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
    switch event {
    case .started: handleStart(task)
    case .progress, .preview, .finished: break
    }
}

// Nuke 14
func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {
    handleStart(task)
}
```

## `Float` to `CGFloat`

The public scale and size APIs now use `CGFloat`, matching the types you get from UIKit and SwiftUI.

| API | Nuke 13 | Nuke 14 |
|---|---|---|
| `ImageRequest.scale` | `Float` | `CGFloat` |
| `ImageRequest.ThumbnailOptions.init(maxPixelSize:)` | `Float` | `CGFloat` |

Literals continue to work as is. Remove the conversions if you had any:

```swift
// Nuke 13
request.scale = Float(traitCollection.displayScale)

// Nuke 14
request.scale = traitCollection.displayScale
```

## `willCache` is now `async`

`ImagePipeline.Delegate.willCache(data:image:for:pipeline:)` returns the data to store instead of taking a completion closure. Return `nil` to prevent caching.

```swift
// Nuke 13
func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline, completion: @escaping (Data?) -> Void) {
    completion(shouldStore(request) ? data : nil)
}

// Nuke 14
func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
    shouldStore(request) ? data : nil
}
```

The method runs on `@ImagePipelineActor`, and the pipeline awaits it before storing the data.

## Renamed `TaskQueue.maxConcurrentOperationCount`

`TaskQueue` has no operations behind it – every unit of work is a Swift `Task` – so it no longer carries the `OperationQueue`-era name. The old name is deprecated and keeps working.

| Nuke 13 | Nuke 14 |
|---|---|
| `TaskQueue.maxConcurrentOperationCount` | `TaskQueue.maxConcurrentTaskCount` |
| `TaskQueue(maxConcurrentOperationCount:)` | `TaskQueue(maxConcurrentTaskCount:)` |

```swift
// Nuke 13
let pipeline = ImagePipeline {
    $0.imageProcessingQueue.maxConcurrentOperationCount = 4
}

// Nuke 14
let pipeline = ImagePipeline {
    $0.imageProcessingQueue.maxConcurrentTaskCount = 4
}
```

## `ImagePipeline.Delegate` declares its isolation

The protocol used to describe where its methods run in a doc comment – "performed on the pipeline queue in the background" – which was true for only half of them. The isolation is now part of each signature.

| Isolation | Methods |
|---|---|
| `@ImagePipelineActor` | `willLoadData`, `willCache`, `imageTaskDidStart`, `imageTask(_:didReceiveEvent:)` |
| `nonisolated` | Everything else: the factories, `cacheKey`, the policies, `decompress`, and `imageTaskCreated` |

A plain method still satisfies an isolated requirement, so most conformers need no changes – only a method with a *conflicting* isolation is now rejected. A `@MainActor` delegate, which previously failed to conform at all, now works.

## `FetchImage.Progress` Replaced by `ImageTask.Progress`

`NukeUI` had a progress type of its own: a nested `ObservableObject` inside another `ObservableObject`, which needed a separate `@ObservedObject` to observe. `FetchImage.progress` and `LazyImageState.progress` now return `ImageTask.Progress` – the same value type the pipeline reports – and `FetchImage` publishes the updates itself.

| API | Nuke 13 | Nuke 14 |
|---|---|---|
| `FetchImage.progress`, `LazyImageState.progress` | `FetchImage.Progress`, a class | `ImageTask.Progress`, a struct |

```swift
// Nuke 13
LazyImage(url: url) { state in
    if state.isLoading {
        DownloadProgressView(progress: state.progress)
    }
}

struct DownloadProgressView: View {
    @ObservedObject var progress: FetchImage.Progress

    var body: some View {
        ProgressView(value: progress.fraction)
    }
}

// Nuke 14
LazyImage(url: url) { state in
    if state.isLoading {
        ProgressView(value: state.progress.fraction)
    }
}
```

`FetchImage.Progress` is now a deprecated typealias for `ImageTask.Progress` and is removed in Nuke 15.

The updates are still only published if you use them: reading `progress` opts the object into publishing them, so a view that doesn't display the progress isn't invalidated every time a chunk of data arrives.

## `NukeUI` surfaces `ImagePipeline.Error`

The pipeline finishes every task with an `ImagePipeline.Error`, so `NukeUI` no longer erases it to `any Error`. Branching on a case no longer needs a cast.

| API | Nuke 13 | Nuke 14 |
|---|---|---|
| `FetchImage.result`, `LazyImageState.result` | `Result<ImageResponse, any Error>?` | `Result<ImageResponse, ImagePipeline.Error>?` |
| `FetchImage.onCompletion`, `LazyImage.onCompletion(_:)`, `LazyImageView.onCompletion` | `(Result<ImageResponse, any Error>) -> Void` | `(Result<ImageResponse, ImagePipeline.Error>) -> Void` |
| `LazyImageState.error`, `LazyImageView.onFailure` | `any Error` | `ImagePipeline.Error` |

```swift
// Nuke 13
LazyImage(url: url) { state in
    if let error = state.error as? ImagePipeline.Error,
       case .dataDownloadExceededMaximumSize = error {
        Text("Image too large")
    }
}

// Nuke 14
LazyImage(url: url) { state in
    if case .dataDownloadExceededMaximumSize = state.error {
        Text("Image too large")
    }
}
```

`FetchImage.load(_:)` still takes an untyped async closure. An error that isn't already an `ImagePipeline.Error` is reported as `dataLoadingFailed(error:)` wrapping it, the same way the pipeline reports the errors thrown by the async `ImageRequest` sources.
