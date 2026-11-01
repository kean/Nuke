---
name: nuke-migrate
description: Upgrade an app to Nuke 14 from Nuke 13 or earlier. Use when bumping the Nuke, NukeUI, or NukeExtensions dependency, when a Nuke upgrade doesn't compile, or when asked to replace NukeExtensions, Combine publishers, or a hand-written GIF view with current Nuke APIs. Finds what the compiler can't report, such as pipeline delegate methods that compile and are never called.
license: MIT
---

# Migrating to Nuke 14

The compiler finds most of this migration, and its errors name the replacements. What it can't find is the dangerous part: code that keeps compiling and stops working. **A green build doesn't mean the migration is done.** Follow the steps in order.

## 1. Check that the app can move

```bash
grep -A6 '"identity" : "nuke"' Package.resolved *.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
grep -rnE 'IPHONEOS_DEPLOYMENT_TARGET|\.iOS\(' --include='*.pbxproj' --include='Package.swift' .
git ls-remote --tags https://github.com/kean/Nuke 'refs/tags/14.*'
```

If there's no `Package.resolved`, read the version from `Package.swift`. Nuke 14 needs iOS 16, tvOS 16, macOS 13, watchOS 9, or visionOS 1, and Xcode 26.0 with Swift 6.2. If the app deploys to something lower, stop and ask. The choice is between raising the target and staying on 13.x, which still gets fixes, and it isn't yours to make.

If the app is on 12.x or earlier, read [From Nuke 12 or earlier](#from-nuke-12-or-earlier) as well.

## 2. List what the compiler won't report

Do this before you touch the dependency, and keep the list. Every hit gets resolved in step 5, whatever the build says.

```bash
# Every conformance to the pipeline delegate
grep -rnE 'ImagePipeline\.Delegate|ImagePipelineDelegate' --include='*.swift' .

# `nil` passed to a LazyImage modifier, and modifiers that take an optional
grep -rnE '\.(processors|priority)\(' --include='*.swift' .

# Error text that reaches people, and errors matched by type in NukeUI callbacks
grep -rn 'localizedDescription' --include='*.swift' .
grep -rnE 'onCompletion|onFailure|\.result|state\.error' --include='*.swift' .

# Views that start playing animations, and repeated loads that used to restart the task
grep -rnE 'LazyImage\(|LazyImageView|FetchImage|onStart' --include='*.swift' .

# Anything that plays, parses, or inspects the encoded data of an image
grep -rnE 'container\.data|imageContainer\?*\.data|\.type == \.gif|Gifu|FLAnimatedImage|SwiftyGif|SDAnimatedImage|makeImageView' --include='*.swift' .

# Queues and prefetchers set by hand, and decoders of your own
grep -rnE 'maxConcurrentRequestCount|ImageDecoding\b|isAsynchronous' --include='*.swift' .
```

The search can't see through a typealias, or a signature split over lines. Open each file and read it.

## 3. Update the dependency

`from: "14.0.0"` doesn't match a prerelease. If the tags from step 1 only have betas, pin one:

```
.package(url: "https://github.com/kean/Nuke", exact: "14.0.0-beta.1")
```

In an Xcode project, change the version rule of the package, and remove the `Package.resolved` entry if it won't update. The product names are the same.

## 4. Fix what the compiler reports

Widely used removed APIs have a stub, and the compiler error says what to do: follow it. `@available(*, unavailable)` stubs can't cover a removed enum case or a property of a removed type, and those are in this table.

| Nuke 13 | Nuke 14 |
|---|---|
| `Nuke_ImageDisplaying`, `nuke_display(image:data:)` | `ImageDisplaying`, `nuke_display(_ container: ImageContainer?)` |
| `ImagePipelineDelegate` | `ImagePipeline.Delegate` |
| `imageId`, `.imageIdKey` | `imageID` |
| `.scaleKey`, `.thumbnailKey` | `request.scale`, `request.thumbnail` |
| A `userInfo` dictionary with those keys | A `var` request with the properties set. It no longer needs `userInfo` |
| `maximumDecodedImageSize` | `ImageRequest.ThumbnailOptions`, per request |
| `ImageRequest(url:, userInfo:)` | `request.userInfo = …` on a `var` |
| `imagePublisher(with:)` | `image(for:)`, or `imageTask(with:)` and `task.previews` |
| `FetchImage.load(publisher)` | `load { try await … }` |
| `case .started` in a delegate | `imageTaskDidStart(_:pipeline:)` |
| `Float(displayScale)` for `scale` or `maxPixelSize` | Remove the conversion, they're `CGFloat` |
| `@ObservedObject var progress: FetchImage.Progress` | `let progress: ImageTask.Progress`, or read `state.progress` in place |
| `state.error as? ImagePipeline.Error` | `state.error`, which is typed |
| `lazyImageView.imageTask = …` | Read-only. Call `cancel()` or `reset()` |
| `dataCache.flush(for: key)` | `await dataCache.flush()`, which writes everything |
| `dataCache.queue` | Removed. Use `await dataCache.flush()` to wait for writes |
| `dataCache.flush()`, `dataCache.sweep()` | `await` them, so the caller becomes `async`, and so do its callers |
| `[String: Any]` for `coreImageFilter(name:parameters:identifier:)` | `[String: any Sendable]` |
| `.failedToApplyFilter(filter:)`, `.failedToCreateOutputCGImage(image:)` | `.failedToApplyFilter(name:)`, `.failedToCreateOutputCGImage(extent:image:)` |
| The static `Configuration.isSignpostLoggingEnabled` | `isDiagnosticsEnabled` on a configuration, which records metrics too. Consider limiting it to debug builds |

Two errors don't say what they're about:

| The compiler says | It's about |
|---|---|
| `value of type 'Never' has no member 'sink'` | `imagePublisher(with:)` |
| `binary operator '~=' cannot be applied to two 'ImageTask.Event' operands` | `case .started` |

A `UIImageView` subclass that overrides the display method has no direct replacement, and it can't conform to `ImageDisplaying` either, because `UIImageView` already does in `NukeExtensions`, and Swift calls that conformance statically. Wrap an image view in a view of your own, and update the code that treated the class as a `UIImageView`:

```swift
import NukeExtensions

final class PosterView: UIView, ImageDisplaying {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func nuke_display(_ container: ImageContainer?) {
        imageView.image = container?.image
    }
}
```

These are deprecated and keep working, so fix them when you touch the code. `maxConcurrentOperationCount` is `maxConcurrentTaskCount`. `isRateLimiterEnabled` does nothing, because the pipeline has no rate limiter, so delete the line. `LazyImageView.isProgressiveImageRenderingEnabled` is `isProgressiveRenderingEnabled`. `task.state` and `task.currentProgress` are `task.status`, which is a struct and not an enum, and `task.progress` is an async sequence:

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

## 5. Fix what the compiler doesn't report

Go through the list from step 2.

### Delegate methods that are never called

Every method of `ImagePipeline.Delegate` has a default implementation, so a method with an old signature compiles, and the pipeline calls the default instead. Nothing warns about it. The one exception is the Nuke 13 `willCache` with its completion closure, which the pipeline still calls.

Compare **every** method in **every** conformance with this list. Any other method whose name matches and whose signature differs is dead:

```swift
extension PipelineDelegate: ImagePipeline.Delegate {
    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? { nil }
    func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> any ImageEncoding { ImageEncoders.Default() }
    func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy { .default(for: context.data) }
    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading { pipeline.configuration.dataLoader }
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest { urlRequest }
    func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)? { pipeline.configuration.imageCache }
    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)? { pipeline.configuration.dataCache }
    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? { nil }
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? { data }
    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool { true }
    func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse { response }
    func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {}
    func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {}
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {}
}
```

The bodies above are not the defaults to copy: leave out what you don't need. Move the conformance into an extension, as above, which is the only place the compiler warns about a method that nearly matches. It doesn't catch a different number of parameters.

The default implementation of the new `willCache` calls the Nuke 13 one, so a delegate that keeps private images off the disk still does. It's soft-deprecated, and if a delegate has both, the pipeline calls the new one, so move the logic over:

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

If the method does more than decide, such as encrypting the data, keep that logic and return the result. Until it moves, note that Nuke 13 didn't wait for the completion closure, and now the image waits for it when the pipeline stores the original data.

These older methods are dead:

| Never called | Use, in `imageTask(_:didReceiveEvent:pipeline:)` |
|---|---|
| `imageTask(_:didUpdateProgress:pipeline:)` | `.progress` |
| `imageTask(_:didReceivePreview:pipeline:)` | `.preview` |
| `imageTaskDidCancel(_:pipeline:)` | `.finished(.failure(.cancelled))`, before any case that matches every failure |
| `imageTask(_:didCompleteWithResult:pipeline:)` | `.finished` |

### `nil` in `LazyImage` modifiers

`.processors(nil)` used to remove the request's processors, and `.priority(nil)` used to reset the priority to `.normal`. Both now keep the request's value. If the request has neither, as with `LazyImage(url:)`, nothing changes.

Otherwise, find out what the view is meant to do. A comment or the design wins over what the code did on 13, which may have been a bug. If nothing says, keep what it did on 13, as here. Either way, tell the owner, because it changes what shipped:

```swift
// Nuke 13
LazyImage(request: request)
    .processors(isBlurred ? [ImageProcessors.GaussianBlur()] : nil)
    .priority(isSelected ? .high : nil)

// Nuke 14
LazyImage(request: request)
    .processors(isBlurred ? [ImageProcessors.GaussianBlur()] : [])
    .priority(isSelected ? .high : .normal)
```

### `localizedDescription`

`ImagePipeline.Error` and `DataLoader.Error` now return a technical sentence in English, which can include a URL, rather than the system's generic text. It's fine in a log. Anywhere a person reads it, show your own message.

### Errors in NukeUI callbacks

`FetchImage.result`, `LazyImageState.result`, `LazyImageState.error`, and the `onCompletion` and `onFailure` callbacks are typed as `ImagePipeline.Error`. An error thrown from the closure passed to `FetchImage.load(_:)` arrives wrapped in `.dataLoadingFailed(error:)`, so `error as? MyError` always fails, with only a warning. Unwrap it:

```swift
// Nuke 13
if case .failure(let error) = result, let error = error as? PosterError {
    show(error)
}

// Nuke 14
if case .failure(.dataLoadingFailed(let underlying)) = result, let error = underlying as? PosterError {
    show(error)
}
```

### Animated images

A processor now drops `ImageContainer.data` and `ImageContainer.animation`, because they describe the image that went in. On 13, the data survived, so a view could play the original over a processed still. **A GIF with a `.resize` is a still on Nuke 14.** Remove the processor from a request that can be animated: `AnimatedImageView` decodes the frames at the size it displays them. A `thumbnail` request gives you a still too, and has no `data` for a GIF, which 13 attached. If a URL can be a GIF or a large still, the `nuke-optimize` skill has a processor that skips animations.

`LazyImage` with its default content and `LazyImageView` now play animations on their own. On 13, they showed the first frame. Nothing fails, so go through the hits from step 2 and find the screens that can show one. If a design or a comment says it stays still, keep it still. Otherwise, tell the owner which screens start moving:

| To keep a still in | Do |
|---|---|
| A `LazyImageView` | `lazyImageView.imageView.isPlaybackEnabled = false` |
| A `LazyImage` | A `content` closure that shows `state.image` and no `AnimatedImage` |
| Every view | `isAnimatedImageParsingEnabled = false` in the pipeline's configuration |

Two more changes reach users on those screens:

- A GIF with no loop count plays once and rests on its last frame. On 13, it showed the first. To keep it moving, set `playerOptions.loopCount = .infinite` on the `AnimatedImageView`.
- Animations cost more memory. Decoded frames go in `AnimatedImageFramePool`, up to 5% of the device's memory, capped at 128 MB, on top of `ImageCache`, whose limit didn't change. `ImageContainer.data`, which counts against that limit, is now kept for APNG, animated WebP, and HEIC and AVIF sequences as well as GIF. If memory is tight, lower `AnimatedImageFramePool.shared.costLimit`.

A third-party GIF view is now dead weight:

| If the app has | Do |
|---|---|
| The default `LazyImage(url:)` | Nothing. It plays |
| A `content` closure that checks for a GIF and shows a custom view | Replace the view with `AnimatedImage(container:)` |
| `makeImageView` on `LazyImageView` that returns a GIF view | Remove it, `imageView` plays animations |
| A `UIImageView` that needs to play | `AnimatedImageView`, which is a subclass of it |
| A rendering engine that parses `container.data` itself | Keep it, and set `isAnimatedImageParsingEnabled = false` |

`container.data != nil` is a look at the header, and is `true` for a single-frame GIF. To ask whether an image can play, check `container.animation != nil`.

Don't remove a GIF dependency that the app uses for anything but Nuke's images.

### Changed defaults

Most apps have nothing to do here. Check these:

- A custom `ImageDecoding` runs on `imageDecodingQueue` unless it sets `isAsynchronous` to `false`, and two of them can now run at once. Look for `static` or global mutable state, and put it behind a lock.
- `ImageDecoders.Video` follows the preview policy now, and the default one for a video is `.disabled`. An app with `isProgressiveDecodingEnabled` that shows the first frame while a video downloads has to return another policy from `previewPolicy(for:pipeline:)`. The first frame also comes out upright, so remove any rotation the app applies to it.
- `dataLoadingQueue` runs requests below `.normal` in 3 of its 6 slots, so a prefetcher with `maxConcurrentRequestCount` above 3 slows down. If prefetching has to keep up with fast scrolling, restore it:

```swift
ImagePipeline.shared = ImagePipeline {
    $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 6, reservedTaskCount: 0)
}
```

- `FetchImage.load(_:)` and `LazyImageView.request` keep the running task when the same image is already loading, where 13 restarted it. A request that differs only in priority counts as the same image. The task gets the new priority, and `onStart` isn't called again, so code that counts on a restart has to call `reset()` or `cancel()` first.
- `isUsingPrepareForDisplay` is on. It keeps the depth of the image on iOS, tvOS, and visionOS, so a 10-bit HEIC or a 16-bit PNG costs twice the memory, and fewer of them fit in `ImageCache`. An app that shows a lot of them can turn it off.

Also changed, with nothing to do: `imageDecodingQueue` runs 2 at a time. The cache keys didn't change, so users keep what's on disk.

## 6. Verify

1. Build every target, and run the tests.
2. Launch with `NUKE_DIAGNOSTICS_LOG=1`, open the screens with images, and read the lines. `log stream --predicate 'subsystem == "com.github.kean.Nuke.ImagePipeline"'` shows them, and the Troubleshooting article explains them.
3. If a delegate method changed, prove it runs: set a breakpoint or a log in it, and load an image. A test with a mock is better, because it stays.
4. Report what you changed by hand from step 5, one line for each hit from step 2, including the ones that needed nothing. That's what a reviewer can't get from the compiler. If you couldn't run the app, say so, and list 2 and 3 as not done.

## Optional: leave `NukeExtensions`

`NukeExtensions` is soft-deprecated, keeps working, and gives no warning, so this isn't part of the upgrade. Do it only if asked, and in a separate commit. `ImageLoader` from `NukeUI` replaces it, and the migration guide has the full mapping.

```swift
// Nuke 13
import NukeExtensions

let options = ImageLoadingOptions(
    placeholder: UIImage(named: "placeholder"),
    transition: .fadeIn(duration: 0.33),
    failureImage: UIImage(named: "error")
)
loadImage(with: url, options: options, into: imageView)

// Nuke 14
import NukeUI

let presentation = ImageLoader.Presentation(
    placeholder: UIImage(named: "placeholder"),
    transition: .fadeIn(duration: 0.33),
    failureImage: UIImage(named: "error")
)
ImageLoader.load(url, into: imageView, presentation: presentation)
```

| NukeExtensions | NukeUI |
|---|---|
| `ImageLoadingOptions.shared` | A `Presentation` of your own, passed to every load |
| `ImageLoadingOptions.pipeline` | The `pipeline` parameter |
| `ImageLoadingOptions.processors` | `ImageLoader.loader(for: imageView).processors` |
| `isPrepareForReuseEnabled = false` | `ImageLoader.loader(for: imageView).keepsPreviousImage = true` |
| The `progress` closure | The `delegate` of `ImageLoader.loader(for: imageView)` |
| The `completion` closure | `await` the returned `ImageLoader.Handle`'s `result` |
| `cancelRequest(for:)` | `ImageLoader.loader(for: imageView).cancel()` |
| A custom `ImageDisplaying` view | `ImageLoader.load(_:into:render:)` |
| `contentModes`, `tintColors` | `ImageLoader.load(_:into:render:)` calling `Presentation.render(_:in:)` |

## From Nuke 12 or earlier

Go straight to 14. The stubs name the replacements for what was removed in Nuke 12 and 13: `ImageRequestConvertible`, `callbackQueue`, `LazyImage(source:)`, `onSuccess`, and the like. Older names fail with "no member": look them up in the migration guide of the version that removed them. What the stubs can't cover:

- **Cancellation** is `.finished(.failure(.cancelled))`, and `pipeline.image(for:)` throws `ImagePipeline.Error.cancelled`, not `CancellationError`. A `catch is CancellationError` compiles and never matches, so it shows an error for a scroll.
- **The typed errors** make a `catch` clause infer `ImagePipeline.Error` when everything in the `do` throws it.
- **Callbacks** are `@MainActor @Sendable`.
- **`ImagePipeline.Configuration`** queues are `TaskQueue`, not `OperationQueue`.

The older guides are in `Documentation/Migrations` in the checkout. Use them to find out what a change was, not for code: their samples are for those versions.
