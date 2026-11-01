# Nuke 14 Migration Guide

This guide eases the transition of the existing apps that use Nuke 13.x to the latest version of the framework.

> Nuke 14 is a work in progress. The guide is updated as the changes land.

## Minimum Requirements

The minimum supported platforms have been raised.

- iOS 16.0, tvOS 16.0, macOS 13.0, watchOS 9.0, visionOS 1.0
- Xcode 26.0
- Swift 6.2

Apps that need to support earlier OS versions can stay on Nuke 13.x, which continues to receive fixes.

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

`NukeExtensions` itself is soft-deprecated, and its replacement doesn't need the protocol – see [`ImageLoader` Replaces `NukeExtensions`](#imageloader-replaces-nukeextensions).

## `LazyImage` and `LazyImageView` Play Animated Images

Nuke 13 showed the first frame of an animated image. In Nuke 14, `LazyImage` with its default content and every `LazyImageView` play GIF, APNG, animated WebP, and HEIC and AVIF sequences. Your code compiles as it is, so the images in your feeds start moving when you update.

A `content` closure that shows `state.image` keeps showing the first frame. To play the image there, use `AnimatedImage`:

```swift
LazyImage(url: url) { state in
    if let container = state.imageContainer, let animation = AnimatedImage(container: container) {
        animation.resizable().scaledToFill()
    } else if let image = state.image {
        image.resizable().scaledToFill()
    }
}
```

Animated images cost memory that Nuke 13 didn't use:

- **Decoded frames** go in `AnimatedImageFramePool`, which holds up to 5% of the device's memory, capped at 128 MB. That comes on top of `ImageCache`, whose default limit is unchanged at 15%, capped at 768 MB. To give the pool less, set `AnimatedImageFramePool.shared.costLimit`.
- **Encoded data:** `ImageContainer.data` is now also kept for APNG, animated WebP, and HEIC and AVIF sequences, where Nuke 13 kept it for GIF only. It counts against the `ImageCache` limit along with the bitmap, so these images take up more of the cache, whether they ever play or not.

A GIF with no loop count plays once and rests on its last frame, which is how browsers play it. Nuke 13 showed its first frame. To keep such a GIF moving, set `loopCount`:

```swift
lazyImageView.imageView.playerOptions.loopCount = .infinite
```

### Keeping a Still

To show the first frame in a `LazyImageView`, turn off playback in its image view:

```swift
lazyImageView.imageView.isPlaybackEnabled = false
```

In a `LazyImage`, pass a `content` closure that shows `state.image`:

```swift
LazyImage(url: url) { state in
    if let image = state.image {
        image.resizable().scaledToFill()
    }
}
```

To keep a still in every view, turn off parsing, which leaves them nothing to play:

```swift
ImagePipeline.shared = ImagePipeline {
    $0.isAnimatedImageParsingEnabled = false
}
```

### Parsed Animations

`ImageDecoders.Default` now parses an animated image and attaches the result to the new `ImageContainer.animation`, so a view that played the encoded data has less to do:

```swift
// Nuke 13
if response.container.type == .gif, let data = response.container.data {
    gifView.animate(withGIFData: data)
}

// Nuke 14
if let animation = response.container.animation {
    imageView.animation = animation
}
```

`imageView` is an `AnimatedImageView` here, a `UIImageView` (an `NSImageView` on macOS) that plays animated images.

The parse runs once per decoded image, off the main thread, and the result is cached with the container. `container.data != nil` is a header sniff and is `true` for a single-frame GIF. `container.animation != nil` is the parsed answer, so prefer it when the question is "can this be played?".

The parse walks the metadata of every frame and is paid whether or not the image is ever displayed. `isAnimatedImageParsingEnabled` turns it off in an app that plays animations some other way, or none at all. `ImageContainer.data` is unaffected by the flag, so a renderer that parses the data itself keeps working.

### Processors and Thumbnails

**A processor now drops `data` and `animation`**, which describe the image that went in. Nuke 13 kept `data`, so a GIF view could play the original over a processed still. A GIF with a `.resize` is a still in Nuke 14. Remove the processor from a request that can be animated, because `AnimatedImageView` decodes the frames no larger than it displays them:

```swift
// Nuke 13
let request = ImageRequest(url: url, processors: [.resize(width: 320)])
let response = try await ImagePipeline.shared.imageTask(with: request).response
gifView.animate(withGIFData: response.container.data!) // Now `nil`

// Nuke 14
let response = try await ImagePipeline.shared.imageTask(with: ImageRequest(url: url)).response
if let animation = response.container.animation {
    imageView.animation = animation
}
```

To change the frames of an animation that goes on playing, use `AnimatedImagePlayer.Options.frameTransform`. A processor of your own that implements `process(_:context:)` decides for itself and can keep both.

**A `thumbnail` request carries no `data` for a GIF** and no `animation`, because playing the full-size animation would undo the downscaling. Nuke 13 attached the data.

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
| `ImagePipeline.Configuration.isSignpostLoggingEnabled` | `ImagePipeline.Configuration.isDiagnosticsEnabled` and `signpostLog` |
| `NukeUI.ImageRequest` | `ImageRequest`, which `NukeUI` re-exports from `Nuke` |

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

The compiler can only say so if `imagePublisher(with:)` stands alone. When a call to `sink` follows it, the error reads `value of type 'Never' has no member 'sink'`.

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

Swift can't attach a message to a removed enum case, so the compiler doesn't name the replacement. The error reads `binary operator '~=' cannot be applied to two 'ImageTask.Event' operands`, `reference to member 'started' cannot be resolved without a contextual type`, or `type 'ImageTask.Event' has no member 'started'`.

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

> Warning: **The Nuke 13 method still compiles, and the pipeline never calls it.** Every delegate method has a default implementation, so nothing requires yours, and the compiler has no way to tell you that it became dead code. A delegate that used `willCache` to keep private images off the disk stops doing so, silently. Search your code for `completion: @escaping (Data?) -> Void`.

The same goes for every other delegate method whose signature doesn't match, such as the Nuke 12 `imageTaskDidCancel(_:pipeline:)`. Declare the conformance in an extension, not on the class:

```swift
final class MyDelegate: Sendable {}

extension MyDelegate: ImagePipeline.Delegate {
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) -> URLRequest? {
        // warning: instance method 'willLoadData(for:urlRequest:pipeline:)' nearly matches
        // defaulted requirement 'willLoadData(for:urlRequest:pipeline:)' of protocol 'Delegate'
    }
}
```

The compiler only compares a method to the requirements of the protocol the extension declares, and only if the number of parameters is the same. So the warning catches the method above, but not the old `willCache`, which has one more parameter.

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

## Removed the Rate Limiter

The pipeline no longer rate limits the requests it starts. The limiter held them in a single queue ahead of `dataLoadingQueue`, which already runs requests in priority order and cancels the pending ones for free, so all it could do was delay work or run a prefetch ahead of an image on screen. `ImagePrefetcher` caps its own requests at 2.

`isRateLimiterEnabled` is deprecated, and setting it does nothing. Delete the line.

```swift
// Nuke 13
let pipeline = ImagePipeline {
    $0.isRateLimiterEnabled = false
}

// Nuke 14
let pipeline = ImagePipeline()
```

## Renamed `ImageTask.taskId`

`ImageTask.taskId` is now `taskID`, which is how every other identifier in Nuke spells it. The old name is deprecated and keeps working.

```swift
// Nuke 13
logger.log("Finished \(task.taskId)")

// Nuke 14
logger.log("Finished \(task.taskID)")
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

## `switch` Needs `@unknown default`

`ImagePipeline.Error`, `DataLoader.Error`, `ImageDecodingError`, and `ImageProcessingError` are now `@nonexhaustive`, like the new `ImageLoader.Event` and the enums of `ImagePipeline.Diagnostics` and `ImageTask.Metrics`. A 14.x release can add a case to any of them without breaking your build, which is what a new failure mode or a retry stage needs.

Outside of the Nuke package, an exhaustive `switch` over one of them is an error in the Swift 6 language mode and a warning in Swift 5 mode: `switch covers known cases, but 'ImagePipeline.Error' may have additional unknown values`. Add `@unknown default`, and the compiler warns you about a case you don't handle when a later release adds one.

```swift
// Nuke 13
switch error {
case .dataLoadingFailed(let error): show(error)
case .dataDownloadExceededMaximumSize: showTooLarge()
case .cancelled: break
case .dataMissingInCache, .dataIsEmpty, .decoderNotRegistered, .decodingFailed,
     .processingFailed, .imageRequestMissing, .pipelineInvalidated:
    showGenericFailure()
}

// Nuke 14
switch error {
case .dataLoadingFailed(let error): show(error)
case .dataDownloadExceededMaximumSize: showTooLarge()
case .cancelled: break
case .dataMissingInCache, .dataIsEmpty, .decoderNotRegistered, .decodingFailed,
     .processingFailed, .imageRequestMissing, .pipelineInvalidated:
    showGenericFailure()
@unknown default:
    showGenericFailure()
}
```

`if case`, `guard case`, and a `switch` that ends in `default` aren't affected. `ImageTask.Event` stays `@frozen`, so a `switch` over it needs nothing.

## `nil` in `LazyImage` modifiers keeps the request's value

`LazyImage.processors(_:)` and `LazyImage.priority(_:)` used to treat `nil` as an empty or default value that replaced the request's own. It now leaves the request's value alone.

| Modifier | Nuke 13 | Nuke 14 |
|---|---|---|
| `.processors(nil)` | Removes the request's processors | Keeps the request's processors |
| `.priority(nil)` | Sets the priority to `.normal` | Keeps the request's priority |

A non-nil value still replaces the request's value, and the last call wins: `.processors([a]).processors(nil)` leaves the request's own processors, so `nil` also takes back an earlier call. If you relied on `nil` to remove the request's processors, pass `[]` instead:

```swift
// Nuke 13
LazyImage(request: request)
    .processors(isBlurred ? [ImageProcessors.GaussianBlur()] : nil)

// Nuke 14
LazyImage(request: request)
    .processors(isBlurred ? [ImageProcessors.GaussianBlur()] : [])
```

## `ImageLoader` Replaces `NukeExtensions`

`NukeExtensions` is soft-deprecated. It keeps working in Nuke 14, but its replacement is `ImageLoader` in `NukeUI`. Like `loadImage(with:into:)`, it starts the load synchronously, so an image found in the memory cache is displayed before it returns, and a new load into the same view cancels the previous one.

```swift
// NukeExtensions
import NukeExtensions

let options = ImageLoadingOptions(
    placeholder: UIImage(named: "placeholder"),
    transition: .fadeIn(duration: 0.33),
    failureImage: UIImage(named: "error")
)
loadImage(with: url, options: options, into: imageView)

// NukeUI
import NukeUI

let presentation = ImageLoader.Presentation(
    placeholder: UIImage(named: "placeholder"),
    transition: .fadeIn(duration: 0.33),
    failureImage: UIImage(named: "error")
)
ImageLoader.load(url, into: imageView, presentation: presentation)
```

`load` returns an `ImageLoader.Handle` instead of taking a completion closure. Await it where you need the outcome:

```swift
// NukeExtensions
loadImage(with: url, into: imageView) { result in
    if case .failure(let error) = result {
        print(error)
    }
}

// NukeUI
let handle = ImageLoader.load(url, into: imageView)
Task {
    if case .failure(let error) = await handle.result {
        print(error)
    }
}
```

The options that applied to every load into a view now live on the loader attached to it, which `ImageLoader.loader(for:)` returns.

| NukeExtensions | NukeUI |
|---|---|
| `loadImage(with:options:into:)` | `ImageLoader.load(_:into:presentation:pipeline:)` |
| `ImageLoadingOptions.placeholder`, `failureImage`, `transition`, `failureImageTransition` | `ImageLoader.Presentation`, same names |
| `ImageLoadingOptions.shared` | A `Presentation` of your own, passed to every load |
| `ImageLoadingOptions.pipeline` | The `pipeline` parameter |
| `ImageLoadingOptions.processors`, `isProgressiveRenderingEnabled` | `ImageLoader.loader(for: imageView)`, same names |
| `ImageLoadingOptions.isPrepareForReuseEnabled = false` | `ImageLoader.loader(for: imageView).keepsPreviousImage = true` |
| The `progress` closure | The `delegate` of `ImageLoader.loader(for: imageView)` |
| The `completion` closure | `await` the returned `ImageLoader.Handle` |
| The returned `ImageTask?` | `ImageLoader.Handle.task` |
| `cancelRequest(for:)` | `ImageLoader.loader(for: imageView).cancel()` |
| `ImageDisplaying`, `alwaysTransition` | `ImageLoader.load(_:into:render:)` |
| `contentModes`, `tintColors` | `ImageLoader.load(_:into:render:)` calling `Presentation.render(_:in:)` |

`ImageLoader` has no shared options: a `Presentation` is a value, so define the ones your app uses once and pass them by name.

If you stay on `NukeExtensions`, a closure passed to `ImageLoadingOptions.Transition.custom(_:)` is now `@MainActor @Sendable`.

To display the image in a view of your own – one that used to conform to `ImageDisplaying` – pass a closure that draws the `ImageLoader.State`:

```swift
// NukeExtensions
extension PosterView: ImageDisplaying {
    func nuke_display(_ container: ImageContainer?) {
        self.image = container?.image
    }
}

loadImage(with: url, into: posterView)

// NukeUI
ImageLoader.load(url, into: posterView) { posterView, state in
    posterView.image = state.image
}
```

To change the content mode or the tint color with the state, call `render(_:in:)` of a `Presentation` from the closure, and change them after it:

```swift
// NukeExtensions
let options = ImageLoadingOptions(
    placeholder: UIImage(named: "placeholder"),
    contentModes: .init(success: .scaleAspectFill, failure: .center, placeholder: .center)
)
loadImage(with: url, options: options, into: imageView)

// NukeUI
let presentation = ImageLoader.Presentation(placeholder: UIImage(named: "placeholder"))
ImageLoader.load(url, into: imageView) { imageView, state in
    presentation.render(state, in: imageView)
    imageView.contentMode = state.image == nil ? .center : .scaleAspectFill
}
```

## `DataCache` Waits With `async`

`DataCache.flush()` and `DataCache.sweep()` are now `async`, and they return when the work is done. `DataCache.queue` and `flush(for:)` are gone: the cache no longer has a queue of its own to hand out, and a flush writes everything that's staged.

```swift
// Nuke 13
dataCache.storeData(data, for: "key")
dataCache.flush(for: "key")

// Nuke 14
dataCache.storeData(data, for: "key")
await dataCache.flush()
```

## `CoreImageFilter` Is `Sendable`

`ImageProcessors.CoreImageFilter` and `coreImageFilter(name:parameters:identifier:)` now take `[String: any Sendable]`. A parameter value that isn't `Sendable` has to go through a filter you create yourself, with `coreImageFilter(_:identifier:)`.

The cases of its `Error` carry descriptions rather than the Core Image objects.

| Nuke 13 | Nuke 14 |
|---|---|
| `.failedToCreateFilter(name:parameters:)`, with `[String: Any]` | `.failedToCreateFilter(name:parameters:)`, with a `String` |
| `.inputImageIsEmpty(inputImage:)`, with a `PlatformImage` | `.inputImageIsEmpty(inputImage:)`, with a `String` |
| `.failedToApplyFilter(filter:)` | `.failedToApplyFilter(name:)` |
| `.failedToCreateOutputCGImage(image:)` | `.failedToCreateOutputCGImage(extent:image:)` |

## `ImageTask.status` Replaces `state` and `currentProgress`

`ImageTask.State` and `ImageTask.currentProgress` are deprecated and keep working. `ImageTask.status` is one snapshot of everything that changes while a task runs, so the values agree with each other.

```swift
// Nuke 13
if task.state == .running {
    print(task.currentProgress.fraction)
}

// Nuke 14
let status = task.status
if status.result == nil, !status.isCancelled {
    print(status.progress.fraction)
}
```

## Changed Defaults

These compile without changes. Most apps have nothing to do, but they do change what the pipeline does.

| Setting | Nuke 13 | Nuke 14 |
|---|---|---|
| `imageDecodingQueue` | 1 task at a time | 2 |
| `dataLoadingQueue` | Requests below `.normal` can take all 6 slots | At most 3, see `TaskQueue.reservedTaskCount` |
| `isUsingPrepareForDisplay` | `false` | `true` |
| An animated image in `LazyImage` and `LazyImageView` | First frame | Plays |
| Memory for decoded animation frames | None | Up to 5% of the device's memory, capped at 128 MB, on top of `ImageCache` |
| `ImageContainer.data` | GIF only | Also APNG, animated WebP, and HEIC and AVIF sequences, and it counts against the `ImageCache` limit |
| A GIF with no loop count | First frame | Plays once and rests on its last frame |
| `ImageContainer.data` after a processor | Kept | `nil`, and so is `animation` |
| `ImageContainer.data` of a GIF with a `thumbnail` | Kept | `nil` |
| `FetchImage.load(_:)` and `LazyImageView.request` while the same image is loading | Restart the download | Keep the running task and give it the new priority |

See [`LazyImage` and `LazyImageView` Play Animated Images](#lazyimage-and-lazyimageview-play-animated-images) for the animated rows.

A custom decoder with `isAsynchronous` set to `true` can now run alongside another one, so state it shares between instances has to be thread-safe. An `ImagePrefetcher` with `maxConcurrentRequestCount` above 3 now runs in 3 slots. To give it all of them back:

```swift
ImagePipeline.shared = ImagePipeline {
    $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 6, reservedTaskCount: 0)
}
```

`isUsingPrepareForDisplay` keeps the depth of the image on iOS, tvOS, and visionOS, where the old path always drew it to 8 bits per component. A 10-bit HEIC or a 16-bit PNG now costs twice the memory, so fewer of them fit in `ImageCache`, and more of them go over its limit for a single entry. 8-bit images cost the same. If your app shows a lot of these images, weigh that against the faster decompression:

```swift
ImagePipeline.shared = ImagePipeline {
    $0.isUsingPrepareForDisplay = false
}
```

"The same image" for `FetchImage` and `LazyImageView` means a request that differs only in priority, from the same pipeline. The call doesn't report a new start, so `onStart` isn't called again. A load that has finished starts over.

The cache keys didn't change, so the images your users have on disk survive the update.

## `localizedDescription` Describes the Failure

`ImagePipeline.Error` and `DataLoader.Error` now conform to `LocalizedError`. `localizedDescription` used to return the system's generic "The operation couldn't be completed", and it now returns the same technical English sentence as `description`, which can include a URL. If you show it to people, show a message of your own.

## `LazyImageView.imageTask` is read-only

`LazyImageView` now loads with an `ImageLoader`, which owns the task. Call `cancel()` to cancel the load, and `reset()` to also clear the view.

## Renamed `LazyImageView.isProgressiveImageRenderingEnabled`

`LazyImageView` now has the same name for it as `ImageLoader` and `ImageLoadingOptions`. The old name is deprecated and keeps working.

```swift
// Nuke 13
lazyImageView.isProgressiveImageRenderingEnabled = false

// Nuke 14
lazyImageView.isProgressiveRenderingEnabled = false
```
