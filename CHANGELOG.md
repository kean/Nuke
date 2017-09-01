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
- Move `nk_imageTask(_:didFinishWithResponse:options)` method to `ImageLoadingView` protocol, that's really where it belongs to
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
