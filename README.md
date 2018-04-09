<p align="center"><img src="https://cloud.githubusercontent.com/assets/1567433/13918338/f8670eea-ef7f-11e5-814d-f15bdfd6b2c0.png" height="180"/>

<p align="center">
<img src="https://img.shields.io/cocoapods/v/Nuke.svg?label=version">
<img src="https://img.shields.io/badge/supports-CocoaPods%20%7C%20Carthage%20%7C%20SwiftPM-green.svg">
<img src="https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-lightgrey.svg">
<a href="https://travis-ci.org/kean/Nuke"><img src="https://img.shields.io/travis/kean/Nuke/master.svg"></a>
</p>

A powerful **image loading** and **caching** framework which allows for hassle-free image loading in your app.

# <a name="h_features"></a>Features

- Load images into image views or other targets
- Two [cache layers](https://kean.github.io/post/image-caching), fast LRU memory cache
- [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin), [FLAnimatedImage](https://github.com/kean/Nuke-FLAnimatedImage-Plugin), [Gifu](https://github.com/kean/Nuke-Gifu-Plugin) integrations
- Can be used with networking, caching libraries [of your choice](#h_design)
- [RxNuke](https://github.com/kean/RxNuke) with RxSwift extensions
- Automates [prefetching](https://kean.github.io/post/image-preheating) with [Preheat](https://github.com/kean/Preheat) (*deprecated in iOS 10*)
- Small (under 1200 lines), [fast](https://github.com/kean/Image-Frameworks-Benchmark) and reliable

> [Nuke 7](https://github.com/kean/Nuke/tree/nuke7) is in development. If you'd like to contribute or have some suggestions or feature requests please open an issue, a pull request or contact me on [Twitter](https://twitter.com/a_grebenyuk).

# <a name="h_getting_started"></a>Quick Start

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/blob/master/Documentation/Migrations).

This README has five sections:

- Complete [**Usage Guide**](#h_usage) - best place to start
- Detailed [**Image Pipeline**](#h_design) description
- Section dedicated to [**Performance**](h_performance)
- List of available [**Extensions**](#h_plugins)
- List of [**Requirements**](#h_requirements)

More information is available in [**Documentation**](https://github.com/kean/Nuke/blob/master/Documentation/) directory and a full [**API Reference**](http://kean.github.io/Nuke/reference/6.1.1/index.html). When you are ready to install Nuke you can follow an [**Installation Guide**](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Installation%20Guide.md) - all major package managers are supported.

# <a name="h_usage"></a>Usage

#### Loading Images into Targets

You can load an image into an image view with a single line of code:

```swift
Manager.shared.loadImage(with: url, into: imageView)
```

Nuke will automatically load image data, decompress it in the background, store image in memory cache and display it.

> To learn more about the image pipeline [see the next section](#h_design).

`Manager` keeps track of each *target*. When you request an image for a target any previous outstanding requests get cancelled. The same happens automatically when the target is deallocated.

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    ...
    // Prepare image view for reuse.
    cell.imageView.image = nil

    // Previous requests for the image view get cancelled.
    Manager.shared.loadImage(with: url, into: cell.imageView)
    ...
}
```

#### Targets

What can be a *target*? Anything that implements `Target` protocol:

```swift
public protocol Target: class {
    /// Callback that gets called when the request is completed.
    func handle(response: Result<Image>, isFromMemoryCache: Bool)
}
```

Nuke extends `UIImageView` (`NSImageView` on macOS) to adopt `Target` protocol. You can do the same for you own classes.

Protocols are great, but sometimes you might want something a bit more flexible. Fortunately, there is a `loadImage(with:into:handler:)` method which works with arbitrary objects as targets:

```swift
indicator.startAnimating()
Manager.shared.loadImage(with: request, into: view) { [weak view] response, _ in
    view?.image = response.value
    indicator.stopAnimating()
}
```

#### Customizing Requests

Each request is represented by a `Request` struct. A request can be created with either `URL` or `URLRequest`.

```swift
var request = Request(url: url)
// var request = Request(urlRequest: URLRequest(url: url))

// Change memory cache policy:
request.memoryCacheOptions.writeAllowed = false

// Track progress:
request.progress = { completed, total in
    ...
}

// Update the request priority:
request.priority = .high

Manager.shared.loadImage(with: request, into: imageView)
```

#### Processing Images

Nuke can process images for you. The first option is to resize the image using a `Request`:

```swift
/// Target size is in pixels.
Request(url: url, targetSize: CGSize(width: 640, height: 320), contentMode: .aspectFill)
```

To perform a custom tranformation use a `processed(key:closure:)` method. Her's how to create a circular avatar using [Toucan](https://github.com/gavinbunney/Toucan):

```swift
Request(url: url).process(key: "circularAvatar") {
    Toucan(image: $0).maskWithEllipse().image
}
```

All of those APIs are built on top of `Processing` protocol. If you'd like to you can implement your own processors that adopt it. Keep in mind that `Processing` also requires `Equatable` conformance which helps Nuke identify images in memory cache.

> See [Core Image Integration Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Core%20Image%20Integration%20Guide.md) for more info about using Core Image with Nuke

#### Loading Images w/o Targets

You can also use `Manager` to load images directly without a target:

```swift
Manager.shared.loadImage(with: url) {
    // Handle response
}
```

If you'd like to cancel the requests, use a [cancellation token](https://kean.github.io/post/cancellation-token):

```swift
let cts = CancellationTokenSource()
Manager.shared.loadImage(with: url, token: cts.token) {
    // Handle response
}
cts.cancel()
```

#### Using Memory and Disk Cache

Default Nuke's `Manager` has two cache layers.

First, there is a memory cache for storing processed images ready for display. You can get a direct access to this cache:

```swift
// Configure cache
Cache.shared.costLimit = 1024 * 1024 * 100 // 100 MB
Cache.shared.countLimit = 100

// Read and write images
let request = Request(url: url)
Cache.shared[request] = image
let image = Cache.shared[request]

// Clear cache
Cache.shared.removeAll()
```

To store unprocessed image data Nuke uses a `URLCache` instance:

```swift
// Configure cache
DataLoader.sharedUrlCache.diskCapacity = 100
DataLoader.sharedUrlCache.memoryCapacity = 0

// Read and write responses
let request = Request(url: url)
let _ = DataLoader.sharedUrlCache.cachedResponse(for: request.urlRequest)
DataLoader.sharedUrlCache.removeCachedResponse(for: request.urlRequest)

// Clear cache
DataLoader.sharedUrlCache.removeAllCachedResponses()
```

#### Preheating Images

[Preheating](https://kean.github.io/post/image-preheating) (prefetching) means loading images ahead of time in anticipation of their use. Nuke provides a `Preheater` class that does just that:

```swift
let preheater = Preheater(manager: Manager.shared)

let requests = urls.map {
    var request = Request(url: $0)
    request.priority = .low
    return request
}

// User enters the screen:
preheater.startPreheating(for: requests)

// User leaves the screen:
preheater.stopPreheating(for: requests)
```

You can use Nuke in combination with [Preheat](https://github.com/kean/Preheat) library which automates preheating of content in `UICollectionView` and `UITableView`. On iOS 10.0 you might want to use new [prefetching APIs](https://developer.apple.com/reference/uikit/uitableviewdatasourceprefetching) provided by iOS instead.

> Check out [Performance Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md) to see what else you can do to improve performance

#### Using RxNuke

[RxNuke](https://github.com/kean/RxNuke) adds [RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke and enables many common use cases:

- [Going from low to high resolution](https://github.com/kean/RxNuke#going-from-low-to-high-resolution)
- [Loading the first available image](https://github.com/kean/RxNuke#loading-the-first-available-image)
- [Showing stale image while validating it](https://github.com/kean/RxNuke#showing-stale-image-while-validating-it)
- [Load multiple images, display all at once](https://github.com/kean/RxNuke#load-multiple-images-display-all-at-once)
- [Auto retry on failures](https://github.com/kean/RxNuke#auto-retry)
- And [more...](https://github.com/kean/RxNuke#use-cases)

Here's an example of how easy it is to load go flow log to high resolution:

```swift
Observable.concat(loader.loadImage(with: lowResUrl).orEmpty,
                  loader.loadImage(with: highResUtl).orEmpty)
    .subscribe(onNext: { imageView.image = $0 })
    .disposed(by: disposeBag)
```

# Image Pipeline<a name="h_design"></a>

Nuke's image pipeline consists of roughly five stages which can be customized using the following protocols:

|Protocol|Description|
|--------|-----------|
|`DataLoading`|Download (or return cached) image data|
|`DataDecoding`|Convert data into image objects|
|`Processing`|Apply image transformations|
|`Caching`|Store image into memory cache|

All those types come together the way you expect:

1. `Manager` checks if the image is in memory cache (`Caching`). If not it asks `Loader` to load it.
2. `Loader` uses underlying data loader (`DataLoading`) to fetch (or return cached) image data.
3. When the image data is loaded `Loader` decodes (`DataDecoding`) creating an image object.
4. The image is then processed (`Processing`) and returned to `Manager`.
5. `Manager` stores the processed image in the memory cache (`Caching`).

> There are some upcoming changes to this pipeline in Nuke 7.

Nuke is fully asynchronous (non-blocking). Each stage is executed on a separate queue tailored specifically for it. Let's dive into each of those stages.

### Data Loading and Caching

A built-in `DataLoader` class implements `DataLoading` protocol and uses [`Foundation.URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) to load image data. The data is cached on disk using a [`Foundation.URLCache`](https://developer.apple.com/reference/foundation/urlcache) instance, which by default is initialized with a memory capacity of 0 MB (Nuke stores images in memory, not image data) and a disk capacity of 150 MB.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) to learn more about image caching

> See [Third Party Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries) guide to learn how to use a custom data loader or cache

Most developers either implement their own networking layer or use a third-party framework. Nuke supports both of those workflows. You can integrate your custom networking layer by implementing `DataLoading` protocol.

> See [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that implements `DataLoading` protocol using [Alamofire](https://github.com/Alamofire/Alamofire) framework

### Memory Cache

A processed images which are ready to be displayed are stored in a fast in-memory cache (`Cache`). It uses [LRU (least recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm and has a limit which prevents it from using more than ~20% of available RAM. As a good citizen, `Cache` automatically evicts images on memory warnings and removes most of the images when the application enters background.

### Deduplicating Requests

By default `Loader` combines the requests with the same `loadKey` into a single task. The task's priority is set to the highest priority of registered requests and gets updated when requests are added or removed to the task. The task only gets cancelled when all the registered requests are.

> Deduplication can be disabled using `Loader.Options`.

# Performance<a name="h_performance"></a>

Performance is one of the key differentiating factors for Nuke. There are three key components of its performance:

### Main-Thread Performance

The framework has been tuned to do very little work on the main thread. In fact, it's [at least 2.3x faster](https://github.com/kean/Image-Frameworks-Benchmark) than its fastest competitor. There are a number of optimizations techniques that were used to achieve that including: reducing number of allocations, reducing dynamic dispatch, backing some structs by reference typed storage to reduce ARC overhead, etc.

### Robustness Under Stress

A common use case is to dynamically start and cancel requests for a collection view full of images when scrolling at a high speed. There are a number of components that ensure robustness in those kinds of scenarios:

- `Loader` schedules each stage of the image pipeline on a dedicated queue. Each queue limits the number of concurrent tasks. This way we don't use too much system resources at any given moment and each stage doesn't block the other. For example, if the image doesn't require processing, it doesn't go through the processing queue.
- Under stress `Loader` will rate limit the requests to prevent trashing of the underlying systems (e.g. `URLSession`).

### Memory Usage

- Nuke tries to free memory as early as possible.
- Memory cache uses [LRU (least recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm. It has a limit which prevents it from using more than ~20% of available RAM. As a good citizen, `Cache` automatically evicts images on memory warnings and removes most of the images when the application enters background.

# Extensions<a name="h_plugins"></a>

|Name|Description|
|--|--|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples of common use cases solved by Rx|
|[**Alamofire**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire) and combine the power of both frameworks|
|[**Gifu**](https://github.com/kean/Nuke-Gifu-Plugin)|Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs|
|[**FLAnimatedImage**](https://github.com/kean/Nuke-AnimatedImage-Plugin)|Use [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) to load and display [animated GIFs]((https://www.youtube.com/watch?v=fEJqQMJrET4))|


# Requirements<a name="h_requirements"></a>

- iOS 9.0 / watchOS 2.0 / macOS 10.10 / tvOS 9.0
- Xcode 9
- Swift 4

# License

Nuke is available under the MIT license. See the LICENSE file for more info.
