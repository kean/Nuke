## Nuke 7.1

### Improvements

- Improve deduplication. Now when creating two requests (at roughly the same time) for the same images but with two different processors, the original image is going to be downloaded once (used to be twice in the previous implementation) and then two separate processors are going to be applied (if the processors are the same, the processing will be performed once).
- Greatly improved test coverage.

### Fixes

- Fix an issue when setting custom `loadKey` for the request, the `hashValue` of the default key was still used.
- Fix warnings "Decoding failed with error code -1" when progressively decoding images. This was the result of `ImageDecoder` trying to decode incomplete progressive scans.
- Fix an issue where `ImageDecoder` could produce a bit more progressive scans than necessary.


## Nuke 7.0.1

### Additions

- Add a section in README about replacing GIFs with video formats (e.g. `MP4`, `WebM`)
- Add proof of concept in the demo project that demonstrates loading, caching and displaying short `mp4` videos using Nuke

### Fixes

- #161 Fix the contentModes not set when initializing an ImageLoadingOptions object

## Nuke 7.0

Nuke 7 is the biggest release yet. It has a lot of  massive new features, new performance improvements, and some API refinements. Check out new [Nuke website](http://kean.github.io/nuke) to see quick videos showcasing some of the new features.

Nuke 7 is almost completely source-compatible with Nuke 6.

### Progressive JPEG & WebP

Add support for progressive JPEG (built-in) and WebP (build by the [Ryo Kosuge](https://github.com/ryokosuge/Nuke-WebP-Plugin)). See [README](https://github.com/kean/Nuke) for more info. See demo project to see it in action.

Add new `ImageProcessing` protocol which now takes an extra `ImageProcessingContext` parameter. One of its properties is `scanNumber` which allows you to do things like apply blur to progressive image scans reducing blur radius with each new scan ("progressive blur").

### Resumable Downloads (HTTP Range Requests)

If the data task is terminated (either because of a failure or a cancellation) and the image was partially loaded, the next load will resume where it was left off. In many use cases resumable downloads are a massive improvement to user experience, especially on the mobile internet. 

Resumable downloads require server support for [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators (`ETag` and `Last-Modified`).

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


## Nuke 7.0-rc1

This is the final pre-release version. The only thing left to do is finish updating the documentation.

Changes in 7.0-rc1:

### Loading Image into Views

- Add more `ImageLoadingOptions` including `failureImage`, `contentModes` and custom transitions.
- `ImageView` will now automatically prepare itself for reuse (can be disabled via `ImageLoadingOptions`)
- Add `ImageDisplaying` protocol and relax the requirement what can be used as an image view (it's `UIView & ImageDisplaying` now). This achieves two things: 
    - You can now add support for more classes (e.g. `MKAnnotationView` by implementing `ImageDisplaying` protocol
    - You can override the `display(image:` method in `UIImageView` subclasses (e.g. `FLAnimatedImageView`).

### image Processing

- Update new `ImageProcessing` protocol to add additional `ImageProcessingContext` parameter. This enabled features like `_ProgressiveBlurImageProcessor` which blurs only first few scans of the progressive image with each new scan having reduced blur radius (see Progressive JPEG Demo).

### Animated Images

- Add built-in support for animated images (everything except the actual rendering). To enable rendering you're still going to need a plugin (see FLAnimatedImage and Gifu plugins). The changes made in Nuke dramatically simplify those plugins making both of them essentially obsolete (they both now have 10-30 lines of code).

### Misc

- Simplify `ImagePipeline` closure-based API. Remove `progressiveImageHandler`, pass partial images into existing `progress` closure.
- Improve test coverage of new features.


## Nuke 7.0-beta3

This is the final beta version. The release version is going to be available next week.

### Aggressive Disk Cache (Beta)

Add a completely new custom LRU disk cache which can be used for fast and reliable *aggressive* (no validation) data caching. The new cache lookups are up to 2x faster than `URLCache` lookups. You can enable it using pipeline's configuration:

```swift
$0.enableExperimentalAggressiveDiskCaching(keyEncoder: {
    guard let data = $0.cString(using: .utf8) else { return nil }
    return _nuke_sha1(data, UInt32(data.count))
})
```

When enabling disk cache you must provide a `keyEncoder` function which takes image request's url as a parameter and produces a key which can be used as a valid filename. The [demo project uses sha1](https://gist.github.com/kean/f5e1975e01d5e0c8024bc35556665d7b) to generate those keys.

The public API for disk cache and the API for using custom disk caches is going to be available the future versions.

> Existing API already allows you to use custom disk cache [by implementing `DataLoading` protocol](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries), but this is not the most straightforward option.

### Memory Cache Improvements

- New `ImageCaching` protocol for memory cache with methods like `func storeResponse(_ response: ImageRespone, for request: ImageRequest)` (it use to be just `subscript[key: AnyHashable] -> Image?`. You can do much more intelligent things in your cache implementations now (e.g. make decisions on when to evict image based on HTTP headers). Plus there is more room for optimization (get rid of AnyHashable overhead).
- Improve cache write/hit/miss performance by 30% by getting rid of AnyHashable overhead. `ImageRequest` `cacheKey` and `loadKey` are now optional. If you use them, Nuke is going to use them instead of built-in internal `ImageRequest.CacheKey` and `ImageRequest.LoadKey`.
- Add `TTL` support in `ImageCache`

### Image Loading Options

Nuke finally has all of the basic convenience options that you would expect from an image loading framework:

```swift
Nuke.loadImage(
    with: url,
    options: ImageLoadingOptions(
        placeholder: UIImage(named: "placeholder"),
        transition: .crossDissolve(0.33)
    ),
    into: imageView
)
```

### Other Changes

- Performance improvements in performance metrics, they are virtually free now
- Performance improvements in `ImageTask` cancellation.
- Add progress to `ImageTask`. Progress object is created lazily (it's creation is relatively expensive)
- Deprecate `Result` type. It was only used in a single completion handler so it didn't really justify its existence. More imporantly, in case of image loading you're really just interested in whether the image was loaded or not. The error is there mostly for diagnostics. We also no longer pollute users' project with yet another `Result` implementation.
- `ImageTask.Completion` now gives you `ImageResponse` (image + URLResponse) instead of just plain image.
- More generic `Cancellable` protocol instead of `DataLoadingTask`


## Nuke 7.0-beta2

### Progressive Image Loading (Beta)

You need a pipeline with progressive decoding enabled:

```swift
let pipeline = ImagePipeline {
    $0.isProgressiveDecodingEnabled = true
}
```

And that's it, you can start observing images as they are produced by the pipeline:

```swift
let imageView = UIImageView()
let task = pipeline.loadImage(with: url) {
    imageView.image = $0.value
}
task.progressiveImageHandler = {
    imageView.image = $0
}
```

The progressive decoding only kicks in when Nuke determines that the image data does contain a progressive JPEG. The decoder intelligently scans the data and only produces a new image when it receives a full new scan (progressive JPEGs normally have around 10 scans).

> See "Progressive Decoding" demo to see progressive JPEG in practice. You can also uncomment the code that blurs the first few scans of the image which makes them look a bit nicer.

### Resumable Data (Beta)

- Mov resumable data implementation to the pipeline which means it will automatically start working with Alamofire plugin and other custom loaders
- Fix an issue with `206 Partial Content` handling
- Add a test suite
- Add `ImagePipeline.Configuration.isResumableDataEnabled flag` (enabled by default)
- Add support for `ETag` (beta1 only had support for `Last-Modified`).

### Performance Metrics (Beta)

- Extend a number of metrics introduced in Nuke 7.0-beta1
- Nicer debug output:

```swift
(lldb) po task.metrics

Task Information {
    Task ID - 5
    Total Duration - 0.363
    Was Cancelled - false
    Is Memory Cache Hit - false
    Was Subscribed To Existing Image Loading Session - false
}
Timeline {
    12:42:06.559 - Start Date
    12:42:06.923 - End Date
}
Image Loading Session {
    Session Information - {
        Session ID - 5
        Total Duration - 0.357
        Was Cancelled - false
    }
    Timeline {
        12:42:06.566 - Start Date
        12:42:06.570 - Data Loading Start Date
        12:42:06.904 - Data Loading End Date
        12:42:06.909 - Decoding Start Date
        12:42:06.912 - Decoding End Date
        12:42:06.913 - Processing Start Date
        12:42:06.922 - Processing End Date
        12:42:06.923 - End Date
    }
    Resumable Data {
        Was Resumed - nil
        Resumable Data Count - nil
        Server Confirmed Resume - nil
    }
}
```

### Additions

- `Nuke.loadImage(with:into:)` now returns a task (discardable)
- Add `ImageDecoderRegistry` to configure decoders globally
- Add `ImageDecodingContext` to provide as much information as needed to select a decoder

### Improvements

- Smarter `RateLimiter` which no longer attempt to execute pending tasks when the bucket isn't full resulting in idle dispatching of blocks. I've used a CountedSet to see how well it works in practice and it's perfect. Nice small win.
- `RateLimiter` now uses the same sync queue as the `ImagePipeline` reducing a number of dispatched blocks

### Deprecations

- `DataDecoding`, `DataDecoder`, `DataDecoderComposition` - replaced by a new image decoding infrastructure (`ImageDecoding`, `ImageDecoder`, `ImageDecodingRegistry` etc)
- `CancellationToken`, `CancellationTokenSource` - continued to be used internally, if you want to use those types in your own project consider copying them
- `typealias ProgerssHandler` is not nested in `ImageTask` (`ImageTask.ProgressHandler`)


## Nuke 7.0-beta1

Nuke 7 is the next major milestone continuing the trend started in Nuke 6 which makes the framework more pragmatic and mature. Nuke 7 is more ergonomic, fast, and more powerful. 

Nuke `7.0-beta1` is an early released (compared to `6.0-beta1`). There are still some major changes coming in next betas. To make migration easier Nuke 7 is almost fully source compatible with Nuke 6, but many APIs were deprecated and will be removed soon.

There are four major new features in Nuke 7:

### Resumable Downloads (Beta)

If the data task is terminated (either because of a failure or a cancellation) and the image was partially loaded, the next load will resume where it was left off. The resumable downloads are enabled by default.

> By default resumable data is stored in an efficient memory cache. Future versions might include more customization.

In many use, cases reusable downloads are a massive improvement. Next betas will feature more customization options for resumable downloads (e.g. customizable resumable data storage).

### Image Pipelines (Beta)

The previous  `Manager` + `Loading` architecture (terrible naming, responsibilities are often confused) was replaced with a  new unified  `ImagePipeline` class. There is also a new `ImageTask` class which feels the gap where user or pipeline needed to communicate with each other after the request was started.

`ImagePipeline` and `ImageTask` have a bunch of new features:
- In `ImagePipeline.Configuration` you can now provider custom queues (`OperationQueue`) for data loading, decoding and processing (each stage). This way you have more access to queuing (e.g. you can change `qualityOfService`, suspend queues) etc and you can also use the same queue across different pipelines.
- There are two APIs: convenience ones with blocks (`loadImage(with:completion:)`) and new one `imageTask(with:)` which returns new `ImageTask` class which gives you access to more advanced features. To start a task call `resume()` method, to cancel the task call `cancel()`.
- Dynamically change priority of executing tasks.
- Set a custom shared `ImagePipeline`.

### Progressive Image Decoding (WIP)

This feature is still in development and might be coming in one of the next beta.

### Performance Metrics (Beta)

Nuke captures detailed metrics on each image task:

```swift
(lldb) p task.metrics
(Nuke.ImageTaskMetrics) $R2 = {
  taskId = 9
  timeCreated = 545513853.67615998
  timeResumed = 545513853.67778301
  timeCompleted = 545513860.90999401
  session = 0x00007b1c00011100 {
    sessionId = 9
    timeDataLoadingStarted = 545513853.67789805
    timeDataLoadingFinished = 545513853.74310505
    timeDecodingFinished = 545513860.90150297
    timeProcessingFinished = 545513860.90990996
    urlResponse = 0x00007b0800066960 {
      ObjectiveC.NSObject = {}
    }
    downloadedDataCount = 35049
  }
  wasSubscibedToExistingTask = false
  isMemoryCacheHit = false
  wasCancelled = false
}
```

### Improvements

- Improve main-thread performance by another 20%.
- `ImagePreheater` now checks `ImageCache` synchronously before creating tasks which makes it more efficient.

### Removed

- Users were confused by separate set of `loadImage(with:into:handler:)` methods so they were removed. There were adding very little convenience for a lot of mental overhead.  It's fairly easy to reimplement them the way you want

### Reworked

- Prefix all classes with *Image* starting with a new ImagePipeline. This makes code more readable. It felt awkward to use types like ‘Request’ in your project. ‘Request’ is an integral part of ‘Nuke’, but you are only using it in your project once or twice.


## Nuke 6.1.1

- Lower macOS deployment target to 10.10. #156.
- Improve README: add detailed *Image Pipeline* section, *Performance* section, rewrite *Usage* guide

## Nuke 6.1

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


## Nuke 6.0-beta2

- Fix memory leak in `Loader` - regression introduced in `6.0-beta1`
- Get rid of Thread Sanitizer warnings in `CancellationTokenSource` (false positive)
- Improve performance of `CancellationTokenSource`
- Improve `Cache` hits and writes performance by ~15%
- Improve `Loader` performance


## Nuke 6.0-beta1

> About 8 months ago I've started using Nuke in production. The project matured from being a playground for experimenting with Swift features to something that I rely on in my days work. The primary goal behind Nuke 6 is to simplify the project even further, and to get rid of the implementation details leaking into a public API.

Nuke is now Swift 4 only. It's simpler, smaller (< 1000 lines of code) , and faster. It features progress reporting and makes it simpler to create custom data loader (e.g. [Alamofire data loader](https://github.com/kean/Nuke-Alamofire-Plugin)).

### Features

- Implements progress reporting https://github.com/kean/Nuke/issues/81

### Removed APIs 

- Remove global `loadImage(...)` functions https://github.com/kean/Nuke/issues/142
- Remove `Deduplicator` class, make this functionality part of `Loader`. This has a number of benefits: reduced API surface, improves performance by reducing number of queue switching, enables new features like progress reporting.
- Remove `Scheduler`, `AsyncScheduler`, `Loader.Schedulers`, `DispatchQueueScheduler`, `OperationQueueScheduler`. This whole infrastructure was way too excessive.
- Make `RateLimiter` private.

### Improvements 

- Replace `Foundation.OperationQueue` & custom `Foundation.Operation` subclass with a new `Queue` type. It's simpler, faster, and gets rid of pesky Thread Sanitizer warnings https://github.com/kean/Nuke/issues/141
- `DataLoader` now works with `URLRequest`, not `Request`
- `Loader` now always call completion on the main thread.
- Move `URLResponse` validation from `DataDecoder` to `DataLoader`
- Make use of some Swift 4 feature like nested types inside generic types.


## Nuke 5.2

Add support for both Swift 3.2 and 4.0.

## Nuke 5.1.1

- Fix Swift 4 warnings
- Add `DataDecoder.sharedUrlCache` to easy access for shared `URLCache` object
- Add references to [RxNuke](https://github.com/kean/RxNuke)
- Minor improvements under the hood


## Nuke 5.1

- De facto `Manager` has already implemented `Loading` protocol in Nuke 5 (you could use it to load images directly w/o targets). Now it also conforms to `Loading` protocols which gives access to some convenience functions available in `Loading` extensions.
- Add `static func targetSize(for view: UIView) -> CGSize` method to `Decompressor`
- Simpler, faster `Preheater`
- Improved documentation


## Nuke 5.0.1

- #116 `Manager` can now be used to load images w/o specifying a target
- `Preheater` is now initialized with `Manager` instead of object conforming to `Loading` protocol


## Nuke 5.0

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


## Nuke 4.1.2

Bunch of improvements in built-in `Promise`:
- `Promise` now also uses new `Lock` - faster creation, faster locking
- Add convenience `isPending`, `resolution`, `value` and `error` properties
- Simpler implementation migrated from [Pill.Promise](https://github.com/kean/Pill)*

*`Nuke.Promise` is a simplified variant of [Pill.Promise](https://github.com/kean/Pill) (doesn't allow `throws`, adds `completion`, etc). The `Promise` is built into Nuke to avoid fetching external dependencies.


## Nuke 4.1.1

- Fix deadlock in `Cache` - small typo, much embarrassment  😄 (https://github.com/kean/Nuke-Alamofire-Plugin/issues/8)


## Nuke 4.1 ⚡️

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
 

## Nuke 3.2
 
 - Swift 2.3 support
 - Preheating is now thread-safe #75

## Nuke 3.1.2

- #71 ImageViewLoadingController now cancels tasks synchronously, thanks to @adomanico

## Nuke 3.1.1

- Demo project update to support CocoaPods 1.0
- #69 Bitcode support for Carthage builds, thanks to @vincentsaluzzo

## Nuke 3.1.0

- #64 Fix a performance regression: images are now decoded once per DataTask like they used to
- #65 Fix an issue custom on-disk cache (`ImageDiskCaching`) was called `setData(_:response:forTask:)` method when the error wasn't nil
- Add notifications for NSURLSessionTask state changes to enable activity indicators (based on https://github.com/kean/Nuke-Alamofire-Plugin/issues/4)

## Nuke 3.0.0

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

## Nuke 2.3.0

- #60 Add custom on-disk caching support (see `ImageDiskCaching` protocol)
- Reduce dynamic dispatch

## Nuke 2.2.0

- `ImageTask` `suspend` method is deprecated, implementation does nothing
- `ImageLoader` now limits a number of concurrent `NSURLSessionTasks`
- Add `maxConcurrentSessionTaskCount` property to `ImageLoaderConfiguration`
- Add `taskReusingEnabled` property to `ImageLoaderConfiguration`
- Add [Swift Package Manager](https://swift.org/package-manager/) support
- Update documentation

## Nuke 2.1.0
 
- #57 `ImageDecompressor` now uses `CGImageAlphaInfo.NoneSkipLast` for opaque images 
- Add `ImageProcessorWithClosure` that can be used for creating anonymous image filters
- `ImageLoader` ensures thread safety of image initializers by running decoders on a `NSOperationQueue` with `maxConcurrentOperationCount=1`. However, `ImageDecoder` class is now also made thread safe.

## Nuke 2.0.1

- #53 ImageRequest no longer uses NSURLSessionTaskPriorityDefault, which requires CFNetwork that doesn't get added as a dependency automatically

## Nuke 2.0

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

## Nuke 1.4.0

- #46 Add option to disable memory cache storage, thanks to @RuiAAPeres

## Nuke 1.3.0

- Add [Core Image Integration Guide](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide)
- Fill most of the blanks in the documentation
- #47 Fix target size rounding errors in image downscaling (Pyry Jahkola @pyrtsa)
- Add `imageScale` property to `ImageDecoder` class that returns scale to be used when creating `UIImage` (iOS, tvOS, watchOS only)
- Wrap each iteration in `ProcessorComposition` in an `autoreleasepool`


## Nuke 1.2.0

- #20 Add preheating for UITableView (see ImagePreheatControllerForTableView class)
- #41 Enhanced tvOS support thanks to @joergbirkhold
- #39 UIImageView: ImageLoadingView extension no available on tvOS
- Add factory method for creating session tasks in DataLoader
- Improved documentation


## Nuke 1.1.1

- #35 ImageDecompressor now uses `32 bpp, 8 bpc, CGImageAlphaInfo.PremultipliedLast` pixel format which adds support for images in an obscure formats, including 16 bpc images.
- Improve docs


## Nuke 1.1.0

- #25 Add tvOS support
- #33 Add app extensions support for OSX target (other targets were already supported)


## Nuke 1.0.0

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
