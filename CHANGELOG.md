# Nuke 8

## Nuke 8.0.1

*July 21, 2019*

- Remove synchronization in `ImageDecoder` which is no longer needed – [#277](https://github.com/kean/Nuke/issues/277)


## Nuke 8.0

*July 8, 2019*

Nuke 8 is the most powerful, performant, and refined release yet. It contains major advancements it some areas and brings some great new features. One of the highlights of this release is the documentation which was rewritten from the ground up.

> **Cache processed images on disk** · **New built-in image processors** · **ImagePipeline v2** · **Up to 30% faster main thread performance** · **`Result` type** · **Improved deduplication** · **`os_signpost` integration** · **Refined ImageRequest API** · **Smart decompression** · **Entirely new documentation**

Most of the Nuke APIs are source compatible with Nuke 7. There is also a [Nuke 8 Migration Guide](https://github.com/kean/Nuke/blob/master/Documentation/Migrations/Nuke%208%20Migration%20Guide.md) to help with migration.

### Image Processing

#### [#227 Cache Processed Images on Disk](https://github.com/kean/Nuke/pull/227)

`ImagePipeline` now supports caching of processed images on disk. To enable this feature set `isDataCacheForProcessedDataEnabled` to `true` in the pipeline configuration and provide a `dataCache`. You can use a built-in `DataCache` introduced in [Nuke 7.3](https://github.com/kean/Nuke/releases/tag/7.3) or write a custom one.

Image cache can significantly improve the user experience in the apps that use heavy image processors like Gaussian Blur.

#### [#243 New Image Processors](https://github.com/kean/Nuke/pull/243)

Nuke now ships with a bunch of built-in image processors including:

-  `ImageProcessor.Resize`
-  `ImageProcessor.RoundedCorners`
-  `ImageProcessor.Circle`
-  `ImageProcessor.GaussianBlur`
-  `ImageProcessor.CoreImageFilter`

There are also `ImageProcessor.Anonymous` to create one-off processors from closures and `ImageProcessor.Composition` to combine two or more processors.

#### [#245 Simplified Processing API](https://github.com/kean/Nuke/pull/245)

Previously Nuke offered multiple different ways to add processors to the request. Now there is only one, which is also better than all of the previous versions:

```swift
let request = ImageRequest(
    url: URL(string: "http://..."),
    processors: [
        ImageProcessor.Resize(size: CGSize(width: 44, height: 44), crop: true),
        ImageProcessor.RoundedCorners(radius: 16)
    ]
)
```

> Processors can also be set using a respective mutable `processors` property.

> Notice that `AnyImageProcessor` is gone! You can simply use `ImageProcessing` protocol directly in places where previously you had to use a type-erased version.


#### [#229 Smart Decompression](https://github.com/kean/Nuke/pull/229)

In the previous versions, decompression was part of the processing API and `ImageDecompressor` was the default processor set for each image request. This was mostly done to simplify implementation but it was confusing for the users.

In the new version, decompression runs automatically and it no longer a "processor". The new decompression is also _smarter_. It runs only when needed – when we know that image is still in a compressed format and wasn't decompressed by one of the image processors.

Decompression runs on a new separate `imageDecompressingQueue`. To disable decompression you can set a new `isDecompressionEnabled` pipeline configuration option to `false`.

#### [#247 Avoiding Duplicated Work when Applying Processors](https://github.com/kean/Nuke/pull/247)

The pipeline avoids doing any duplicated work when loading images. Now it also avoids applying the same processors more than once. For example, let's take these two requests:
        
```swift
let url = URL(string: "http://example.com/image")
pipeline.loadImage(with: ImageRequest(url: url, processors: [
    ImageProcessor.Resize(size: CGSize(width: 44, height: 44)),
    ImageProcessor.GaussianBlur(radius: 8)
]))
pipeline.loadImage(with: ImageRequest(url: url, processors: [
    ImageProcessor.Resize(size: CGSize(width: 44, height: 44))
]))
```
        
Nuke will load the image data only once, resize the image once and apply the blur also only once. There is no duplicated work done at any stage. If any of the intermediate results are available in the data cache, they will be used.

### ImagePipeline v2

Nuke 8 introduced a [major new iteration](https://github.com/kean/Nuke/pull/235) of the `ImagePipeline` class. The class was introduced in Nuke 7 and it contained a lot of incidental complexity due to addition of progressive decoding and some other new features. In Nuke 8 it was rewritten to fully embrace progressive decoding. The new pipeline is smaller, simpler, easier to maintain, and more reliable.

It is also faster.

#### +30% Main Thread Performance

The image pipeline spends even less time on the main thread than any of the previous versions. It's up to 30% faster than Nuke 7.

#### [#239 Load Image Data](https://github.com/kean/Nuke/pull/239)

Add a new `ImagePipeline` method to fetch original image data:

```swift
@discardableResult
public func loadData(with request: ImageRequest,
                     progress: ((_ completed: Int64, _ total: Int64) -> Void)? = nil,
                     completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) -> ImageTask
```

This method now powers `ImagePreheater` with destination `.diskCache` introduced in [Nuke 7.4](https://github.com/kean/Nuke/releases/tag/7.4) (previously it was powered by a hacky internal API).

#### [#245 Improved ImageRequest API](https://github.com/kean/Nuke/pull/245)

The rarely used options were extracted into the new `ImageRequestOptions` struct and the request initializer can now be used to customize _all_ of the request parameters.

#### [#255 `filteredURL`](https://github.com/kean/Nuke/pull/255)

You can now provide a `filteredURL` to be used as a key for caching in case the URL contains transient query parameters:

```swift
let request = ImageRequest(
    url: URL(string: "http://example.com/image.jpeg?token=123")!,
    options: ImageRequestOptions(
        filteredURL: "http://example.com/image.jpeg"
    )
)
```

#### [#241 Adopt `Result` type](https://github.com/kean/Nuke/pull/241)

Adopt the `Result` type introduced in Swift 5. So instead of having a separate `response` and `error` parameters, the completion closure now has only one parameter - `result`.

```swift
public typealias Completion = (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void
```

### Performance

Apart from the general performance improvements Nuke now also offers a great way to measure performance and gain visiblity into how the system behaves when loading images.

#### [#250 Integrate `os_signpost`](https://github.com/kean/Nuke/pull/250)

Integrate [os_signpost](https://developer.apple.com/documentation/os/logging) logs for measuring performance. To enable the logs set `ImagePipeline.Configuration.isSignpostLoggingEnabled` (static property) to `true` before accessing the `shared` pipeline.

With these logs, you have visibility into the image pipeline. For more information see [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/) which explains `os_signpost` in a great detail.

<img width="1375" alt="Screenshot 2019-06-01 at 10 46 52" src="https://user-images.githubusercontent.com/1567433/58753519-8adf7b80-84c0-11e9-806a-eac24ddaa2dd.png">

### Documentation

All the documentation for Nuke was rewritten from scratch in Nuke 8. It's now more concise, clear, and it even features some fantastic illustrations:

<img width="1158" alt="Screenshot 2019-06-11 at 22 31 18" src="https://user-images.githubusercontent.com/1567433/59304491-aacd2700-8c98-11e9-9630-293d27545b1a.png">

The screenshots come the the **reworked demo** project. It gained new demos including *Image Processing* demo and also a way to change `ImagePipeline` configuration in runtime.

### Misc

- Add a cleaner way to set `ImageTask` priority using a new `priority` property – [#251](https://github.com/kean/Nuke/pull/251)
- [macOS] Implement image cost calculation for `ImageCache` – [#236](https://github.com/kean/Nuke/issues/236)
- [watchOS] Add `WKInterfaceImage` support
- Future-proof Objective-C `ImageDisplaying` protocol by adding `nuke_` prefixes to avoid clashes in Objective-C runtime
- Add convenience `func decode(data: Data) -> Image?` method with a default `isFinal` argument to `ImageDecoding` protocol – [e3ca5e](https://github.com/kean/Nuke/commit/e3ca5e646ddc1939d05a121de20cf88e2c8220cc)
- Add convenience `func process(image: Image) -> Image?` method to `ImageProcessing` protocol
- `DataCache` will now automatically re-create its root directory if it was deleted underneath it
- Add public `flush` method to `DataCache` 


# Nuke 7

## Nuke 7.6.3

*May 1, 2019*

- Fix [#226](https://github.com/kean/Nuke/issues/226) `ImageTask.setPriority(_:)` sometimes crashes


## Nuke 7.6.2

*Apr 24, 2019*

- Fix [Thread Sanitizer warnings](https://github.com/kean/Nuke/issues/224). The issue was related to `unfair_lock` usage which was introduced as a replacement for `OSAtomic` functions in Nuke 7.6. In order to fix the issue, `unfair_lock` was replaced with simple `NSLock`. The performance hit is pretty insignificant and definitely isn't worth introducing this additional level of complexity.

## Nuke 7.6.1

*Apr 13, 2019*

- Fix SwiftPM 5.0 support by adding explicit platform version requirements  – [Vadim Shpakovski](https://github.com/shpakovski) in [#220](https://github.com/kean/Nuke/pull/220)
- Update [Nuke 7 Migration Guide](https://github.com/kean/Nuke/blob/master/Documentation/Migrations/Nuke%207%20Migration%20Guide.md)


## Nuke 7.6

*Apr 7, 2019*

- Add Swift 5.0 support – [Daniel Storm](https://github.com/DanielStormApps) in [#217](https://github.com/kean/Nuke/pull/217)
- Add SwiftPM 5.0 support – [Vadim Shpakovski](https://github.com/shpakovski) in [#219](https://github.com/kean/Nuke/pull/219)
- Remove Swift 4.0 and Swift 4.1 support
- Remove iOS 9, tvOS 9, watchOS 2.0, macOS 10.10 and macOS 10.11 support
- Add a single `Nuke` target which can build the framework for any platform
- Replace deprecated `OSAtomic` functions with `unfair_lock`, there are no performance regressions


## Nuke 7.5.2

*Dec 26, 2018*

- [macOS] Fix `Nuke.loadImage` image is not displayed when `.fadeIn` transition is used – [#206](https://github.com/kean/Nuke/issues/206)
- Add `.alwaysTransition` flag to `ImageLoadingOptions` – [@gabzsa](https://github.com/gabzsa) in [#201](https://github.com/kean/Nuke/pull/201)


## Nuke 7.5.1

*Nov 8, 2018*

- Update Swift version in pbxproj to Swift 4.2, [#199](https://github.com/kean/Nuke/issues/199)
- Update demo to Swift 4.2


## Nuke 7.5

*Oct 21, 2018*

### Additions

- [#193](https://github.com/kean/Nuke/pull/193) Add an option to `ImageDecompressor` to allow images to upscale, thanks to [@drkibitz](https://github.com/drkibitz)
- [#197](https://github.com/kean/Nuke/pull/197) Add a convenience initializer to `ImageRequest` which takes an image processor (`ImageProcessing`) as a parameter, thanks to [@drkibitz](https://github.com/drkibitz)

### Improvements

- Add a guarantee that if you cancel `ImageTask` on the main thread, you won't receive any more callbacks (progress, completion)
- Improve internal `Operation` performance, images are loading up to 5% faster

### Removals

Nuke 7 had a lot of API changes, to make the migration easier it shipped with Deprecated.swift file (536 line of code) which enabled Nuke 7 to be almost 100% source-compatible with Nuke 6. It's been 6 months since Nuke 7 release, so now it's finally a good time to remove all of this code. 


## Nuke 7.4.2

*Oct 1, 2018*

- #174 Fix an issue with an `ImageView` reuse logic where in rare cases a wrong image would be displayed, thanks to @michaelnisi


## Nuke 7.4.1

*Sep 25, 2018*

- Disable automatic `stopPreheating` which was causing some issues


## Nuke 7.4

*Sep 22, 2018*

### Prefetching Improvements

- Add an `ImagePreheater.Destination` option to `ImagePreheater`. The default option is `.memoryCache` which works exactly the way `ImagePreheater` used to work before. The more interesting option is `.diskCache`. The preheater with `.diskCache` destination will skip image data decoding entirely to reduce CPU and memory usage. It will still load the image data and store it in disk caches to be used later.
- Add convenience `func startPreheating(with urls: [URL])` function which creates requests with `.low` requests for you.
- `ImagePreheater` now automatically cancels all of the managed outstanding requests on deinit.
- Add `UICollectionViewDataSourcePrefetching` demo on iOS 10+. Nuke still supports iOS 9 so [Preheat](https://github.com/kean/Preheat) is also still around.

### Other Changes

- #187 Fix an issue with progress handler reporting incorrect progress for resumed (206 Partial Content) downloads
- Remove `enableExperimentalAggressiveDiskCaching` function from `ImagePipeline.Configuration`, please use `DataCache` directly instead
- Update [Performance Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md)


## Nuke 7.3.2

*Jul 29, 2018*

- #178 Fix TSan warning being triggered by performance optimization in `ImageTask.cancel()` (false positive)
- Fix an issue where a request (`ImageRequest`) with a default processor and a request with the same processor but set manually would have different cache keys 

## Nuke 7.3.1

*Jul 20, 2018*

- `ImagePipeline` now updates the priority of shared operations when the registered tasks get canceled (was previosuly only reacting to added tasks)
- Fix an issue where `didFinishCollectingMetrics` closure wasn't called for the tasks completed with images found in memory cache and the tasks canceled before they got a chance to run. Now _every_ created tasks gets a corresponding `didFinishCollectingMetrics` call.


## Nuke 7.3

*Jun 29, 2018*

This release introduces new `DataCache` type and features some other improvements in custom data caching.

- Add new `DataCache` type - a cache backed by a local storage with an LRU cleanup policy. This type is a reworked version of the experimental data cache which was added in Nuke 7.0. It's now much simpler and also faster. It allows for reading and writing in parallel, it has a simple consistent API, and I hope it's going to be a please to use.

> **Migration note:** The storage format - which is simply a bunch of files in a directory really - is backward compatible with the previous implementation. If you'd like the new cache to continue working with the same path, please create it with "com.github.kean.Nuke.DataCache" name and use the same filename generator that you were using before:
> 
>    try? DataCache(name: "com.github.kean.Nuke.DataCache", filenameGenerator: filenameGenerator)

- #160 `DataCache` now has a default `FilenameGenerator` on Swift 4.2 which uses `SHA1` hash function provided by `CommonCrypto` (`CommonCrypto` is not available on the previous version of Swift).

- #171 Fix a regression introduced in version 7.1. where experimental `DataCache` would not perform LRU data sweeps.

- Update `DataCaching` protocol. To store data you now need to implement a synchronous method `func cachedData(for key: String) -> Data?`. This change was necessary to make the data cache fit nicely in `ImagePipeline` infrastructure where each stage is managed by a separate `OperationQueue` and each operation respects the priority of the image requests associated with it.

- Add `dataCachingQueue` parameter to `ImagePipeline.Configuration`. The default `maxConcurrentOperationCount` is `2`.

- Improve internal `Operation` type performance.


## Nuke 7.2.1

*Jun 18, 2018*

Nuke's [roadmap](https://trello.com/b/Us4rHryT/nuke) is now publicly available. Please feel free to contribute!

This update addresses tech debt introduces in version 7.1 and 7.2. All of the changes made in these version which improved deduplication are prerequisites for implementing smart prefetching which be able to skip decoding, load to data cache only, etc.

### Enhancements

- Simpler and more efficient model for managing decoding and processing operations (including progressive ones). All operations now take the request priority into account. The processing operations are now created per processor, not per image loading session which leads to better performance.
- When subscribing to existing session which already started processing, pipeline will try to find existing processing operation.
- Update `DFCache` integration demo to use new `DataCaching` protocol
- Added ["Default Image Pipeline"](https://github.com/kean/Nuke#default-image-pipeline) section and ["Image Pipeline Overview"](https://github.com/kean/Nuke#image-pipeline-overview) sections in README.
- Update "Third Party Libraries" guide to use new `DataCaching` protocol


## Nuke 7.2

*Jun 12, 2018*

### Additions

- #163 Add `DataCaching` protocol which can be used to implement custom data cache. It's not documented yet, the documentation going to be updated in 7.2.1.

### Improvements

- Initial iOS 12.0, Swift 4.2 and Xcode 10 beta 1 support
- #167 `ImagePipeline` now uses `OperationQueue` instead of `DispatchQueue` for decoding images. The queue now respects `ImageRequest` priority. If the task is cancelled the operation added to a queue is also cancelled. The queue can be configured via `ImagePipeline.Configuration`.
- #167 `ImagePipeline` now updates processing operations' priority.

### Fixes

- Fix a regression where in certain deduplication scenarios a wrong image would be saved in memory cache
- Fix MP4 demo project
- Improve test coverage, bring back `DataCache` (internal) tests


## Nuke 7.1

*May 27, 2018*

### Improvements

- Improve deduplication. Now when creating two requests (at roughly the same time) for the same images but with two different processors, the original image is going to be downloaded once (used to be twice in the previous implementation) and then two separate processors are going to be applied (if the processors are the same, the processing will be performed once).
- Greatly improved test coverage.

### Fixes

- Fix an issue when setting custom `loadKey` for the request, the `hashValue` of the default key was still used.
- Fix warnings "Decoding failed with error code -1" when progressively decoding images. This was the result of `ImageDecoder` trying to decode incomplete progressive scans.
- Fix an issue where `ImageDecoder` could produce a bit more progressive scans than necessary.


## Nuke 7.0.1

*May 16, 2018*

### Additions

- Add a section in README about replacing GIFs with video formats (e.g. `MP4`, `WebM`)
- Add proof of concept in the demo project that demonstrates loading, caching and displaying short `mp4` videos using Nuke

### Fixes

- #161 Fix the contentModes not set when initializing an ImageLoadingOptions object


## Nuke 7.0

*May 10, 2018*

Nuke 7 is the biggest release yet. It has a lot of  massive new features, new performance improvements, and some API refinements. Check out new [Nuke website](http://kean.github.io/nuke) to see quick videos showcasing some of the new features.

Nuke 7 is almost completely source-compatible with Nuke 6.

### Progressive JPEG & WebP

Add support for progressive JPEG (built-in) and WebP (build by the [Ryo Kosuge](https://github.com/ryokosuge/Nuke-WebP-Plugin)). See [README](https://github.com/kean/Nuke) for more info. See demo project to see it in action.

Add new `ImageProcessing` protocol which now takes an extra `ImageProcessingContext` parameter. One of its properties is `scanNumber` which allows you to do things like apply blur to progressive image scans reducing blur radius with each new scan ("progressive blur").

### Resumable Downloads (HTTP Range Requests)

If the data task is terminated (either because of a failure or a cancellation) and the image was partially loaded, the next load will resume where it was left off. In many use cases resumable downloads are a massive improvement to user experience, especially on the mobile internet. 

Resumable downloads require the server support for [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators (`ETag` and `Last-Modified`).

The resumable downloads are enabled by default. The resumable data is automatically stored in efficient memory cache. This is a good default, but future versions might add more customization options.

### Loading Images into Views

Add a new set of powerful methods to load images into views. Here's one of those methods:

```swift
@discardableResult
public func loadImage(with request: ImageRequest,
                      options: ImageLoadingOptions = ImageLoadingOptions.shared,
                      into view: ImageDisplayingView,
                      progress: ImageTask.ProgressHandler? = nil,
                      completion: ImageTask.Completion? = nil) -> ImageTask?
```

You can now pass `progress` and `completion` closures as well as new  `ImageLoadingOptions` struct which offers a range of options:

```swift
public struct ImageLoadingOptions {
    public static var shared = ImageLoadingOptions()
    public var placeholder: Image?
    public var transition: Transition?
    public var failureImage: Image?
    public var failureImageTransition: Transition?
    public var isPrepareForReuseEnabled = true
    public var pipeline: ImagePipeline?
    public var contentModes: ContentModes?

    /// Content modes to be used for each image type (placeholder, success, failure).
    public struct ContentModes {
        public var success: UIViewContentMode
        public var failure: UIViewContentMode
        public var placeholder: UIViewContentMode
    }

    /// An animated image transition.
    public struct Transition {
        public static func fadeIn(duration: TimeInterval, options: UIViewAnimationOptions = [.allowUserInteraction]) -> Transition
        public static func custom(_ closure: @escaping (ImageDisplayingView, Image) -> Void) -> Transition
    }
}
```

`ImageView` will now also automatically prepare itself for reuse (can be disabled via `ImageLoadingOptions`)

Instead of an `ImageTarget` protocol we now have a new simple `ImageDisplaying` protocol which relaxes the requirement what can be used as an image view (it's `UIView & ImageDisplaying` now). This achieves two things:

- You can now add support for more classes (e.g. `MKAnnotationView` by implementing `ImageDisplaying` protocol
- You can override the `display(image:` method in `UIImageView` subclasses (e.g. `FLAnimatedImageView`)

### Image Pipeline

The previous  `Manager` + `Loading` architecture (terrible naming, responsibilities are often confusing) was replaced with a  new unified  `ImagePipeline` class. `ImagePipeline` was built from the ground-up to support all of the powerful new features in Nuke 7 (progressive decoding, resumable downloads, performance metrics, etc).

There is also a new `ImageTask` class which feels the gap where user or pipeline needed to communicate between each other after the request was started. `ImagePipeline` and `ImageTask` offer a bunch of new features:

- To cancel the request you now simply need to call `cancel()` on the task (`ImageTask`) which is a bit more user-friendly than previous `CancellationTokenSource` infrastructure.
- `ImageTask` offers a new way to track progress (in addition to closures) - native `Foundation.Progress` (created lazily)
- `ImageTask` can be used to dynamically change the priority of the executing tasks (e.g. the user opens a new screen, you lower the priority of outstanding tasks)
- In `ImagePipeline.Configuration` you can now provide custom queues (`OperationQueue`) for data loading, decoding and processing (separate queue for each stage).
- You can set a custom shared `ImagePipeline`.

### Animated Images (GIFs)

Add built-in support for animated images (everything expect the actual rendering). To enable rendering you're still going to need a third-party library (see [FLAnimatedImage](https://github.com/kean/Nuke-FLAnimatedImage-Plugin) and [Gifu](https://github.com/kean/Nuke-Gifu-Plugin) plugins). The changes made in Nuke dramatically simplified those plugins making both of them essentially obsolete - they both now have 10-30 lines of code, you can just copy this code into your project.

### Memory Cache Improvements

- Add new `ImageCaching` protocol for memory cache which now works with a new `ImageRespone` class. You can do much more intelligent things in your cache implementations now (e.g. make decisions on when to evict image based on HTTP headers).
- Improve cache write/hit/miss performance by 30% by getting rid of AnyHashable overhead. `ImageRequest` `cacheKey` and `loadKey` are now optional. If you use them, Nuke is going to use them instead of built-in internal `ImageRequest.CacheKey` and `ImageRequest.LoadKey`.
- Add `TTL` support in `ImageCache`

### Aggressive Disk Cache (Experimental)

Add a completely new custom LRU disk cache which can be used for fast and reliable *aggressive* data caching (ignores [HTTP cache control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)). The new cache lookups are up to 2x faster than `URLCache` lookups. You can enable it using pipeline's configuration:

When enabling disk cache you must provide a `keyEncoder` function which takes image request's url as a parameter and produces a key which can be used as a valid filename. The [demo project uses sha1](https://gist.github.com/kean/f5e1975e01d5e0c8024bc35556665d7b) to generate those keys.

```swift
$0.enableExperimentalAggressiveDiskCaching(keyEncoder: {
    guard let data = $0.cString(using: .utf8) else { return nil }
    return _nuke_sha1(data, UInt32(data.count))
})
```

The public API for disk cache and the API for using custom disk caches is going to be available in the future versions.

> Existing API already allows you to use custom disk cache [by implementing `DataLoading` protocol](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries), but this is not the most straightforward option.

### Performance Metrics

When optimizing performance, it's important to measure. Nuke collects detailed performance metrics during the execution of each image task:

```swift
ImagePipeline.shared.didFinishCollectingMetrics = { task, metrics in
    print(metrics)
}
```

![timeline](https://user-images.githubusercontent.com/1567433/39193766-8dfd81b2-47dc-11e8-86b3-f3f69dc73d3a.png)

```
(lldb) po metrics

Task Information {
    Task ID - 1
    Duration - 22:35:16.123 – 22:35:16.475 (0.352s)
    Was Cancelled - false
    Is Memory Cache Hit - false
    Was Subscribed To Existing Session - false
}
Session Information {
    Session ID - 1
    Total Duration - 0.351s
    Was Cancelled - false
}
Timeline {
    22:35:16.124 – 22:35:16.475 (0.351s) - Total
    ------------------------------------
    nil – nil (nil)                      - Check Disk Cache
    22:35:16.131 – 22:35:16.410 (0.278s) - Load Data
    22:35:16.410 – 22:35:16.468 (0.057s) - Decode
    22:35:16.469 – 22:35:16.474 (0.005s) - Process
}
Resumable Data {
    Was Resumed - nil
    Resumable Data Count - nil
    Server Confirmed Resume - nil
}
```

### Other Changes

- `ImagePreheater` now checks `ImageCache` synchronously before creating tasks which makes it slightly more efficient.
- `RateLimiter` now uses the same sync queue as the `ImagePipeline` reducing a number of dispatched blocks
- Smarter `RateLimiter` which no longer attempt to execute pending tasks when the bucket isn't full resulting in idle dispatching of blocks. I've used a CountedSet to see how well it works in practice and it's perfect. Nice small win.
- Add `ImageDecoderRegistry` to configure decoders globally.
- Add `ImageDecodingContext` to provide as much information as needed to select a decoder.
- `ImageTask.Completion` now contains `ImageResponse` (image + URLResponse) instead of just plain image.

### Deprecations

- `CancellationToken`, `CancellationTokenSource` - continued to be used internally, If you'd like to continue using cancellation tokens please consider copying this code into your project.
- `DataDecoding`, `DataDecoder`, `DataDecoderComposition` - replaced by a new image decoding infrastructure (`ImageDecoding`, `ImageDecoder`, `ImageDecodingRegistry` etc).
- `Request` renamed to `ImageRequest`.
- Deprecate `Result` type. It was only used in a single completion handler so it didn't really justify its existence. More importantly, I wasn't comfortable providing a public `Result` type as part of the framework.


# Nuke 6

## Nuke 6.1.1

*Apr 9, 2018*

- Lower macOS deployment target to 10.10. #156.
- Improve README: add detailed *Image Pipeline* section, *Performance* section, rewrite *Usage* guide


## Nuke 6.1

*Feb 24, 2018*

### Features

- Add `Request.Priority` with 5 available options ranging from `.veryLow` to `.veryHigh`. One of the use cases of `Request.Priority` is to lower the priority of preheating requests. In case requests get deduplicated the task's priority is set to the highest priority of registered requests and gets updated when requests are added or removed from the task.

### Improvements

- Fix warnings on Xcode 9.3 beta 3
- `Loader` implementation changed a bit, it is less clever now and is able to accommodate new features like request priorities
- Minor changes in style guide to make codebase more readable
- Switch to native `NSLock`, there doesn't seem to be any performance wins anymore when using `pthread_mutex` directly

### Fixes

- #146 fix disk cache path for macOS, thanks to @willdahlberg


## Nuke 6.0

*Dec 23, 2017*

> About 8 months ago I finally started using Nuke in production. The project has matured from a playground for experimenting with Swift features to something that I rely on in my day's job.

There are three main areas of improvements in Nuke 6:

- Performance. Nuke 6 is fast! The primary `loadImage(with:into:)` method is now **1.5x** faster thanks to performance improvements of [`CancellationToken`](https://kean.github.io/post/cancellation-token), `Manager`, `Request` and `Cache` types. And it's not just main thread performance, many of the background operations were also optimized.
- API refinements. Some common operations that were surprisingly hard to do are not super easy. And there are no more implementation details leaking into a public API (e.g. classes like `Deduplicator`).
- Fixes some inconveniences like Thread Sanitizer warnings (false positives!). Improved compile time. Better documentation.

### Features

- Implements progress reporting https://github.com/kean/Nuke/issues/81
- Scaling images is now super easy with new convenience `Request` initialisers (`Request.init(url:targetSize:contentMode:` and `Request.init(urlRequest:targetSize:contentMode:`)
- Add a way to add anonymous image processors to the request (`Request.process(key:closure:)` and `Request.processed(key:closure:)`)
- Add `Loader.Options` which can be used to configure `Loader` (e.g. change maximum number of concurrent requests, disable deduplication or rate limiter, etc).

### Improvements

- Improve performance of [`CancellationTokenSource`](https://kean.github.io/post/cancellation-token), `Loader`, `TaskQueue`
- Improve `Manager` performance by reusing contexts objects between requests
- Improve `Cache` by ~30% for most operations (hits, misses, writes)
- `Request` now stores all of the parameters in the underlying reference typed container (it used to store just reference typed ones). The `Request` struct now only has a single property with a reference to an underlying container.
- Parallelize image processing for up to 2x performance boost in certain scenarios. Might increase memory usage. The default maximum number of concurrent tasks is 2 and can be configured using `Loader.Options`.
- `Loader` now always call completion on the main thread.
- Move `URLResponse` validation from `DataDecoder` to `DataLoader`
- Make use of some Swift 4 feature like nested types inside generic types.
- Improve compile time.
- Wrap `Loader` processing and decoding tasks into `autoreleasepool` which reduced memory footprint.

### Fixes

- Get rid of Thread Sanitizer warnings in `CancellationTokenSource` (false positive)
- Replace `Foundation.OperationQueue` & custom `Foundation.Operation` subclass with a new `Queue` type. It's simpler, faster, and gets rid of pesky Thread Sanitizer warnings https://github.com/kean/Nuke/issues/141

### Removed APIs

- Remove global `loadImage(...)` functions https://github.com/kean/Nuke/issues/142
- Remove static `Request.loadKey(for:)` and `Request.cacheKey(for:)` functions. The keys are now simply returned in `Request`'s `loadKey` and `cacheKey` properties which are also no longer optional now.
- Remove `Deduplicator` class, make this functionality part of `Loader`. This has a number of benefits: reduced API surface, improves performance by reducing the number of queue switching, enables new features like progress reporting.
- Remove `Scheduler`, `AsyncScheduler`, `Loader.Schedulers`, `DispatchQueueScheduler`, `OperationQueueScheduler`. This whole infrastructure was way too excessive.
- Make `RateLimiter` private.
- `DataLoader` now works with `URLRequest`, not `Request`


# Nuke 5

## Nuke 5.2

*Sep 1, 2017*

Add support for both Swift 3.2 and 4.0.


## Nuke 5.1.1

*Jun 11, 2017*

- Fix Swift 4 warnings
- Add `DataDecoder.sharedUrlCache` to easy access for shared `URLCache` object
- Add references to [RxNuke](https://github.com/kean/RxNuke)
- Minor improvements under the hood


## Nuke 5.1

*Feb 23, 2017*

- De facto `Manager` has already implemented `Loading` protocol in Nuke 5 (you could use it to load images directly w/o targets). Now it also conforms to `Loading` protocols which gives access to some convenience functions available in `Loading` extensions.
- Add `static func targetSize(for view: UIView) -> CGSize` method to `Decompressor`
- Simpler, faster `Preheater`
- Improved documentation


## Nuke 5.0.1

*Feb 2, 2017*

- #116 `Manager` can now be used to load images w/o specifying a target
- `Preheater` is now initialized with `Manager` instead of object conforming to `Loading` protocol


## Nuke 5.0

* Feb 1, 2017*

### Overview

Nuke 5 is a relatively small release which removes some of the complexity from the framework.

One of the major changes is the removal of promisified API as well as `Promise` itself. Promises were briefly added in Nuke 4 as an effort to simplify async code. The major downsides of promises are compelex memory management, extra complexity for users unfamiliar with promises, complicated debugging, performance penalties. Ultimately I decided that promises were adding more problems that they were solving. 

### Changes

#### Removed promisified API and `Promise` itself

- Remove promisified API, use simple closures instead. For example, `Loading` protocol's method `func loadImage(with request: Request, token: CancellationToken?) -> Promise<Image>` was replaced with a method with a completion closure `func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)`. The same applies to `DataLoading` protocol.
- Remove `Promise` class
- Remove `PromiseResolution<T>` enum
- Remove `Response` typealias
- Add `Result<T>` enum which is now used as a replacement for `PromiseResolution<T>` (for instance, in `Target` protocol, etc)

#### Memory cache is now managed exclusively by `Manager`

- Remove memory cache from `Loader`
- `Manager` now not only reads, but also writes to `Cache`
- `Manager` now has new methods to load images w/o target (Nuke 5.0.1) 

The reason behind this change is to reduce confusion about `Cache` usage. In previous versions the user had to pass `Cache` instance to both `Loader` (which was both reading and writing to cache asynchronously), and to `Manager` (which was just reading from the cache synchronously). In a new setup it's clear who's responsible for managing memory cache.

#### Removed `DataCaching` and `CachingDataLoader`

Those two types were included in Nuke to make integrating third party caching libraries a bit easier. However, they were actually not that useful. Instead of using those types you could've just wrapped `DataLoader` yourself with a comparable amount of code and get much more control. For more info see [Third Party Libraries: Using Other Caching Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries). 

#### Other Changes

- `Loader` constructor now provides a default value for `DataDecoding` object
- `DataLoading` protocol now works with a `Nuke.Request` and not `URLRequest` in case some extra info from `URLRequest` is required
- Reduce default `URLCache` disk capacity from 200 MB to 150 MB
- Reduce default `maxConcurrentOperationCount` of `DataLoader` from 8 to 6
- Shared objects (like `Manager.shared`) are now constants.
- `Preheater` is now initialized with `Manager` instead of `Loading` object
- Add new [Third Party Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md) guide.
- Improved documentation


# Nuke 4

## Nuke 4.1.2

*Oct 22, 2016*

Bunch of improvements in built-in `Promise`:
- `Promise` now also uses new `Lock` - faster creation, faster locking
- Add convenience `isPending`, `resolution`, `value` and `error` properties
- Simpler implementation migrated from [Pill.Promise](https://github.com/kean/Pill)*

*`Nuke.Promise` is a simplified variant of [Pill.Promise](https://github.com/kean/Pill) (doesn't allow `throws`, adds `completion`, etc). The `Promise` is built into Nuke to avoid fetching external dependencies.


## Nuke 4.1.1

*Oct 4, 2016*

- Fix deadlock in `Cache` - small typo, much embarrassment  😄 (https://github.com/kean/Nuke-Alamofire-Plugin/issues/8)


## Nuke 4.1 ⚡️

*Oct 4, 2016*

Nuke 4.1 is all about **performance**. Here are some notable performance improvements:

- `loadImage(with:into:)` method with a default config is **6.3x** faster
- `Cache` operations (write/hit/miss) are from **3.1x** to **4.5x** faster

Nuke 4.0 focused on stability first, naturally there were some performance regressions. With the version 4.1 Nuke is again [the fastest framework](https://github.com/kean/Image-Frameworks-Benchmark) out there. The performance is ensured by a new set of performance tests.

<img src="https://cloud.githubusercontent.com/assets/1567433/19019388/26463bb2-888f-11e6-87dd-42c2d82c5dae.png" width="500"/>

If you're interested in the types of optimizations that were made check out recent commits. There is a lot of awesome stuff there!

Nuke 4.1 also includes a new [Performance Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md) and a collection of [Tips and Tricks](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Tips%20and%20Tricks.md).

### Other Changes

- Add convenience method `loadImage(with url: URL, into target: AnyObject, handler: @escaping Handler)` (more useful than anticipated).
- #88 Add convenience `cancelRequest(for:)` function
- Use `@discardableResult` in `Promise` where it makes sense
- Simplified `Loader` implementation
- `Cache` nodes are no longer deallocated recursively on `removeAll()` and `deinit` (I was hitting stack limit in benchmarks, it's impossible in real-world use).
- Fix: All `Cache` public `trim()` methods are now thread-safe too.


## Nuke 4.0 🚀

*Sep 19, 2016*

### Overview
 
Nuke 4 has fully adopted the new **Swift 3** changes and conventions, including the new [API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).
 
Nuke 3 was already a slim framework. Nuke 4 takes it a step further by simplifying almost all of its components.
 
Here's a few design principles adopted in Nuke 4:
 
- **Protocol-Oriented Programming.** Nuke 3 promised a lot of customization by providing a set of protocols for loading, caching, transforming images, etc. However, those protocols were vaguely defined and hard to implement in practice. Protocols in Nuke 4 are simple and precise, often consisting of a single method.
- **Single Responsibility Principle.** For example, instead of implementing preheating and deduplicating of equivalent requests in a single vague `ImageManager` class, those features were moved to separate classes (`Preheater`, `Deduplicator`). This makes core classes much easier to reason about.
- **Principle of Least Astonishment**. Nuke 3 had a several excessive protocols, classes and methods which are *all gone* now (`ImageTask`, `ImageManagerConfiguration` just to name a few). Those features are much easier to use now.
- **Simpler Async**. Image loading involves a lot of asynchronous code, managing it was a chore. Nuke 4 adopts two design patterns ([**Promise**](https://github.com/kean/Promise) and **CancellationToken**) that solve most of those problems.
 
The adoption of those design principles resulted in a simpler, more testable, and more concise code base (which is now under 900 slocs, compared to AlamofireImage's 1426, and Kingfisher's whopping 2357).
 
I hope that Nuke 4 is going to be a pleasure to use. Thanks for your interest 😄
 
You can learn more about Nuke 4 in an in-depth [**Nuke 4 Migration Guide**](https://github.com/kean/Nuke/blob/master/Documentation/Migrations/Nuke%204%20Migration%20Guide.md).

### Highlighted New Features
 
#### LRU Memory Cache
 
Nuke 4 features a new custom LRU memory cache which replaced `NSCache`. The primary reason behind this change was the fact that `NSCache` [is not LRU](https://github.com/apple/swift-corelibs-foundation/blob/master/Foundation/NSCache.swift). The new `Nuke.Cache` has some other benefits like better performance, and more control which would enable some new advanced features in future versions.

#### Rate Limiter
 
There is a known problem with `URLSession` that it gets trashed pretty easily when you resume and cancel `URLSessionTasks` at a very high rate (say, scrolling a large collection view with images). Some frameworks combat this problem by simply never cancelling `URLSessionTasks` which are already in `.running` state. This is not an ideal solution, because it forces users to wait for cancelled requests for images which might never appear on the display.
 
Nuke has a better, classic solution for this problem - it introduces a new `RateLimiter` class which limits the rate at which `URLSessionTasks` are created. `RateLimiter` uses a [token bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm. The implementation supports quick bursts of requests which can be executed without any delays when "the bucket is full". This is important to prevent the rate limiter from affecting "normal" requests flow. `RateLimiter` is enabled by default.
 
You can see `RateLimiter` in action in a new `Rate Limiter Demo` added in the sample project.

#### Toucan Plugin

Make sure to check out new [Toucan plugin](https://github.com/kean/Nuke-Toucan-Plugin) which provides a simple API for processing images. It supports resizing, cropping, rounded rect masking and more.
 

# Nuke 3

## Nuke 3.2

*Sep 8, 2016*
 
 - Swift 2.3 support
 - Preheating is now thread-safe #75


## Nuke 3.1.3

*Jul 17, 2016*

#72 Fix synchronization issue in ImageManager loader:task:didFinishWithImage... method


## Nuke 3.1.2

*Jul 14, 2016*

- #71 ImageViewLoadingController now cancels tasks synchronously, thanks to @adomanico


## Nuke 3.1.1

*Jun 7, 2016*

- Demo project update to support CocoaPods 1.0
- #69 Bitcode support for Carthage builds, thanks to @vincentsaluzzo


## Nuke 3.1

*Apr 15, 2016*

- #64 Fix a performance regression: images are now decoded once per DataTask like they used to
- #65 Fix an issue custom on-disk cache (`ImageDiskCaching`) was called `setData(_:response:forTask:)` method when the error wasn't nil
- Add notifications for NSURLSessionTask state changes to enable activity indicators (based on https://github.com/kean/Nuke-Alamofire-Plugin/issues/4)


## Nuke 3.0

*Mar 26, 2016*

- Update for Swift 2.2
- Move `ImagePreheatController` to a standalone package [Preheat](https://github.com/kean/Preheat)
- Remove deprecated `suspend` method from `ImageTask`
- Remove `ImageFilterGaussianBlur` and Core Image helper functions which are now part of [Core Image Integration Guide](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide)
- Cleanup project structure (as expected by SPM)
- `Manager` constructor now has a default value for configuration
- `nk_setImageWith(URL:)` method no longer resizes images by default, because resizing is not effective in most cases
- Remove `nk_setImageWith(request:options:placeholder:)` method, it's trivial
- `ImageLoadingView` default implementation no longer implements "Cross Dissolve" animations, use `ImageViewLoadingOptions` instead (see `animations` or `handler` property)
- Remove `ImageViewDefaultAnimationDuration`, use `ImageViewLoadingOptions` instead (see `animations` property)
- `ImageDisplayingView` protocol now has a single `nk_displayImage(_)` method instead of a `nk_image` property
- Remove `nk_targetSize` property from `UI(NS)View` extension


# Nuke 2

## Nuke 2.3

*Mar 19, 2016*

- #60 Add custom on-disk caching support (see `ImageDiskCaching` protocol)
- Reduce dynamic dispatch


## Nuke 2.2

*Mar 11, 2016*

- `ImageTask` `suspend` method is deprecated, implementation does nothing
- `ImageLoader` now limits a number of concurrent `NSURLSessionTasks`
- Add `maxConcurrentSessionTaskCount` property to `ImageLoaderConfiguration`
- Add `taskReusingEnabled` property to `ImageLoaderConfiguration`
- Add [Swift Package Manager](https://swift.org/package-manager/) support
- Update documentation


## Nuke 2.1

*Feb 27, 2016*
 
- #57 `ImageDecompressor` now uses `CGImageAlphaInfo.NoneSkipLast` for opaque images 
- Add `ImageProcessorWithClosure` that can be used for creating anonymous image filters
- `ImageLoader` ensures thread safety of image initializers by running decoders on a `NSOperationQueue` with `maxConcurrentOperationCount=1`. However, `ImageDecoder` class is now also made thread safe.


## Nuke 2.0.1

*Feb 10, 2016*

- #53 ImageRequest no longer uses NSURLSessionTaskPriorityDefault, which requires CFNetwork that doesn't get added as a dependency automatically


## Nuke 2.0

*Feb 6, 2016*

Nuke now has an [official website](http://kean.github.io/Nuke/)!

#### Main Changes

- #48 Update according to [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/). All APIs now just feel right.
- Add `UIImage` extension with helper functions for `Core Image`: `nk_filter(_:)`, etc.
- Add `ImageFilterGaussianBlur` as an example of a filter on top of `Core Image` framework
- Add `ImageRequestMemoryCachePolicy` enum that specifies the way `Manager` interacts with a memory cache; `NSURLRequestCachePolicy` no longer affects memory cache
- #17 Add `priority` to `ImageRequest`
- Add `removeResponseForKey()` method to `ImageMemoryCaching` protocol and the corresponding method to `Manager`
- Implement congestion control for `ImageLoader` that prevents `NSURLSession` trashing
- Simplify `ImageLoaderDelegate` by combining methods that were customizing processing in a single high-level method: `imageLoader(_:processorFor:image:)`. Users now have more control over processing
- Add `NSURLResponse?` parameter to `decode` method from `ImageDecoding` protocol
- `DataLoading` protocol no longer has `isLoadEquivalentRequest(_:toRequest)` and `isCacheEquivalentRequest(_:toRequest)`. Those methods are now part of `ImageLoaderDelegate` and they have default implementation
- `ImageResponseInfo` is now a struct
- Improved error reporting (codes are now stored in enum, more codes were added, error is now created with a failure reason)

#### UI Extensions Changes
- Move `nk_ImageTask(_:didFinishWithResponse:options)` method to `ImageLoadingView` protocol, that's really where it belongs to
- Add `handler` property to `ImageViewLoadingOptions` that allows you to completely override display/animate logic in `ImageLoadingView`
- Remove `nk_prepareForReuse` method from `ImageLoadingView` extensions (useless)
- Remove `placeholder` from `ImageViewLoadingOptions`, move it to a separate argument which is only available on `ImageDisplayingView`s
- Add `animated`, `userInfo` to `ImageViewLoadingOptions`
- `ImageViewLoadingOptions` is now nonull everywhere
- Add `setImageWith(task:options:)` method to `ImageViewLoadingController`

#### Other Changes

- If you add a completion handler for completed task, the response is now marked as `isFastResponse = true`
- Fix an issue that allowed incomplete image downloads to finish successfully when using built-in networking
- `equivalentProcessors(rhs:lhs:)` function is now private (and it also is renamed)
- Remove public `isLoadEquivalentToRequest(_:)` and `isCacheEquivalentToRequest(_:)` methods from `ImageRequest` extension
- Add `ImageTaskProgress` struct that represents load progress, move `fractionCompleted` property from `ImageTask` to `ImageTaskProgress`
- Remove public helper function `allowsCaching` from `ImageRequest` extension
- Remove deprecated `XCPSetExecutionShouldContinueIndefinitely` from playground


# Nuke 1

## Nuke 1.4

*Jan 9, 2016*

- #46 Add option to disable memory cache storage, thanks to @RuiAAPeres


## Nuke 1.3

*Dec 7, 2015*

- Add [Core Image Integration Guide](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide)
- Fill most of the blanks in the documentation
- #47 Fix target size rounding errors in image downscaling (Pyry Jahkola @pyrtsa)
- Add `imageScale` property to `ImageDecoder` class that returns scale to be used when creating `UIImage` (iOS, tvOS, watchOS only)
- Wrap each iteration in `ProcessorComposition` in an `autoreleasepool`


## Nuke 1.2

*Nov 15, 2015*

- #20 Add preheating for UITableView (see ImagePreheatControllerForTableView class)
- #41 Enhanced tvOS support thanks to @joergbirkhold
- #39 UIImageView: ImageLoadingView extension no available on tvOS
- Add factory method for creating session tasks in DataLoader
- Improved documentation


## Nuke 1.1.1

*Oct 30, 2015*

- #35 ImageDecompressor now uses `32 bpp, 8 bpc, CGImageAlphaInfo.PremultipliedLast` pixel format which adds support for images in an obscure formats, including 16 bpc images.
- Improve docs


## Nuke 1.1

*Oct 23, 2015*

- #25 Add tvOS support
- #33 Add app extensions support for OSX target (other targets were already supported)


## Nuke 1.0

*Oct 18, 2015*

- #30 Add new protocols and extensions to make it easy to add full featured image loading capabilities to custom UI components. Here's how it works:
```swift
extension MKAnnotationView: ImageDisplayingView, ImageLoadingView {
    // That's it, you get default implementation of all the methods in ImageLoadingView protocol
    public var nk_image: UIImage? {
        get { return self.image }
        set { self.image = newValue }
    }
}
```
- #30 Add UIImageView extension instead of custom UIImageView subclass
- Back to the Mac! All new protocol and extensions for UI components (#30) are also available on a Mac, including new NSImageView extension.
- #26 Add `getImageTaskWithCompletion(_:)` method to Manager
- Add essential documentation
- Add handy extensions to ImageResponse


# Nuke 0.x

## Nuke 0.5.1

*Oct 13, 2015*

Nuke is now available almost [everywhere](https://github.com/kean/Nuke/wiki/Supported-Platforms). Also got rid of CocoaPods subspecs.

### New Supported Platforms

- CocoaPods, Nuke, watchOS
- CocoaPods, Nuke, OSX
- CocoaPods, NukeAlamofirePlugin, watchOS
- CocoaPods, NukeAlamofirePlugin, OSX
- Carthage, Nuke, watchOS
- Carthage, Nuke, OSX
- Carthage, NukeAlamofirePlugin, iOS
- Carthage, NukeAlamofirePlugin, watchOS
- Carthage, NukeAlamofirePlugin, OSX

### Repo Changes

- Remove Nuke/Alamofire subspec, move sources to separate repo [Nuke-Alamofire-Plugin](https://github.com/kean/Nuke-Alamofire-Plugin)
- Remove Nuke/GIF subspec, move sources to separate repo [Nuke-AnimatedImage-Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin)

### Code Changes

- #9, #19 ImageTask now has a closure for progress instead of NSProgress
- Rename ImageLoadingDelegate to ImageLoadingManager
- Add ImageLoaderDelegate with factory method to construct image decompressor, and `shouldProcessImage(_:)` method
- Make ImageRequest extensions public
- Make ImageTask constructor public; Annotate abstract methods.


## Nuke 0.5

*Oct 9, 2015*

This is a pre-1.0 version, first major release which is going to be available soon.

### Major

- #18 ImageTask can now be suspended (see `suspend()` method). Add `suspendLoadingForImageTask(_:)` method to `ImageLoading` protocol
- #24 ImageRequest can now be initialized with NSURLRequest. ImageDataLoading `imageDataTaskWithURL(_:progressHandler:completionHandler:)` method changed to `imageDataTaskWithRequest(_:progressHandler:completionHandler:)`. First parameter is ImageRequest, return value change from NSURLSessionDataTask to NSURLSessionTask.
- ImageLoader no longer limits number of concurrent NSURLSessionTasks (which had several drawbacks)
- Add base ImagePreheatingController class
- Multiple preheating improvements: significantly simplified implementation; visible index paths are now subtracted from preheat window; performance improvements.

### Minor

- BUGFIX: When subscribing to an existing NSURLSessionTask user was receiving progress callback with invalid totalUnitCount
- Add public `equivalentProcessors(lhs:rhs:) -> Bool` function that works on optional processors
- Add essential documentation


## Nuke 0.4

*Oct 4, 2015*

### Major

- Make ImageLoading protocol and ImageLoader class public
- Make ImageManager `cachedResponseForRequest(_:)` and `storeResponse(_:forRequest:)` methods public
- Make ImageRequestKey class and ImageRequestKeyOwner protocol public
- Remove unused ImageManaging and ImagePreheating protocols 

### Minor

- #13 BUGFIX: Crash on 32-bit iOS simulator on Mac with 16Gb+ of RAM (@RuiAAPeres)
- BUGFIX: Processing operation might not get cancelled in certain situations
- ImageProcessing protocol now provides default implementation for `isEquivalentToProcessor(_:)` method including separate implementation for processors that also conform to Equatable protocol.
- Add identifier: Int property to ImageTask
- ImageRequestKey now relies on Hashable and Equatable implementation provided by NSObject
- ImageMemoryCaching protocol now works with ImageRequestKey class

### Plumbing

- Adopt multiple Swift best practices (tons of them in fact)
- ImageManager is now fully responsible for memory caching and preheating, doesn't delegate any work to ImageLoader (simplifies its implementation and limits dependencies)
- Remove ImageRequestKeyType enum
- Rename ImageManagerLoader to ImageLoader
- Simply ImageManagerLoader (now ImageLoader) implementation
- Add multiple unit tests


## Nuke 0.3.1

*Sep 22, 2015*

#10 Fix Carthage build


## Nuke 0.3

*Sep 21, 2015*

- ImageTask now acts like a promise
- ImageManager.shared is now a property instead of a method
- ImageTask progress is now created lazily
- Add maxConcurrentTaskCount to ImageManagerConfiguration
- Move taskWithURL method to ImageManaging extension
- Add ImagePreheating protocol
- Multiple improvements across the board


## Nuke 0.2.2

*Sep 20, 2015*

- Add limited Carthage support (doesn't feature [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) and [Alamofire](https://github.com/Alamofire/Alamofire) integration yet, you'll have to stick with CocoaPods for that)
- ImageTask resume() and cancel() methods now return Self
- ImageTask completion property is now public
- Minor implementation improvements


## Nuke 0.2.1

*Sep 19, 2015*

- Add ImageCollectionViewPreheatingController (yep)
- Add [Image Preheating Guide](https://github.com/kean/Nuke/wiki/Image-Preheating-Guide)
- Add preheating demo


## Nuke 0.2

*Sep 18, 2015*

#### Major

- Optional [Alamofire](https://github.com/Alamofire/Alamofire) integration via 'Nuke/Alamofire' subspec
- Optional [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) integration via 'Nuke/GIF' subspec
- More concise API
- Add image filters to ImageRequest
- Add ImageManaging protocol
- Add ImageDecoderComposition
- Add ImageProcessorComposition
- watchOS
- Add convenience functions that forward calls to the shared manager

#### Minor

- Use ErrorType
- Add removeAllCachedImages method
- ImageRequest userInfo is now Any? so that you can pass anything including closures
- ImageResponseInfo now has userInfo: Any? property
- ImageResponseInfo is now a struct
- CachedImageResponse renamed to ImageCachedResponse; userInfo is now Any?
- Multiple improvements across the board


## Nuke 0

*Mar 11, 2015*

- Initial commit
