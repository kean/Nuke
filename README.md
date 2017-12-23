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
- [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin), [FLAnimatedImage](https://github.com/kean/Nuke-FLAnimatedImage-Plugin), [Gifu](https://github.com/kean/Nuke-Gifu-Plugin) extensions
- [Freedom to use](#h_design) networking, caching libraries of your choice
- [RxSwift](https://github.com/ReactiveX/RxSwift) extensions provided by [RxNuke](https://github.com/kean/RxNuke)
- Automated [prefetching](https://kean.github.io/post/image-preheating) with [Preheat](https://github.com/kean/Preheat) library
- Small (~1000 lines), [fast](https://github.com/kean/Image-Frameworks-Benchmark) and reliable


# <a name="h_getting_started"></a>Quick Start

- [Installation Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Installation%20Guide.md)
- [Documentation](https://github.com/kean/Nuke/blob/master/Documentation/)
- [API Reference](http://kean.github.io/Nuke/reference/6.0/index.html)

Upgrading from the previous version? Use a [migration guide](https://github.com/kean/Nuke/blob/master/Documentation/Migrations).

> If you have any questions or comments about Nuke feel free to hit me up on Twitter [@a_grebenyuk](https://twitter.com/a_grebenyuk).

# <a name="h_usage"></a>Usage

#### Loading Images into Targets

You can load an image into an image view with a single line of code. Nuke will automatically load image data, decompress it in the background, cache the image, and display it.

```swift
Manager.shared.loadImage(with: url, into: imageView)
```


#### Reusing Targets

`Nuke.loadImage(with:into:)` method cancels previous outstanding request for a target. Nuke holds a weak reference to the target, when the target is deallocated the request is cancelled.

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    ...
    cell.imageView.image = nil
    Manager.shared.loadImage(with: url, into: cell.imageView)
    ...
}
```


#### Providing Custom Handlers

Nuke has a flexible `loadImage(with:into:handler:)` method which lets you handle the response any way you want. You can use it to implement custom transitions, show loading indicators, and more.

```swift
indicator.startAnimating()
Manager.shared.loadImage(with: request, into: view) { [weak view] response, _ in
    view?.image = response.value
    indicator.stopAnimating()
}
```

> The target in this method is declared as `AnyObject` with which the requests get associated. 


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

Manager.shared.loadImage(with: request, into: imageView)
```

#### Processing Images

Nuke can process and cache loaded images for you. For example, to resize the image you can simply provide the desired size when creating a `Request`:

```swift
/// Target size is in pixels.
let request = Request(url: url, targetSize: CGSize(width: 640, height: 320), contentMode: .aspectFill)
```

It's also easy to perform custom image transformations by providing a closure. For example, here's how you can use [Toucan](https://github.com/gavinbunney/Toucan) to create a circular avatar:

```swift
let request = Request(url: url).process(key: "circularAvatar") {
    Toucan(image: $0).maskWithEllipse().image
}
```

Another way to process images is by implementing custom processors which conform to `Processing` protocol. Each processor should be `Equatable` which helps Nuke store processed images in a memory cache.

> See [Core Image Integration Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Core%20Image%20Integration%20Guide.md) for more info about using Core Image with Nuke


#### Loading Images w/o Targets

You can also use `Manager` to load images directly without a target.

```swift
Manager.shared.loadImage(with: url) {
    print("image \($0.value)")
}
```

If you'd like to cancel the requests, use a [cancellation token](https://kean.github.io/post/cancellation-token):

```swift
let cts = CancellationTokenSource()
Manager.shared.loadImage(with: url, token: cts.token) {
    print("image \($0.value)")
}
cts.cancel()
```


#### Using RxNuke

[RxNuke](https://github.com/kean/RxNuke) adds [RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke and enables many common use cases:

- Going from low to high resolution
- Loading the first available image
- Showing stale image while validating it
- Load multiple images, display all at once
- Auto retry on failures

And [more...](https://github.com/kean/RxNuke#use-cases)


#### Using Memory Cache

You can get a direct access to the default memory cache used by Nuke:

```swift
Cache.shared.costLimit = 1024 * 1024 * 100 // 100 MB
Cache.shared.countLimit = 100

let request = Request(url: url)
Cache.shared[request] = image
let image = Cache.shared[request]
```


#### Preheating Images

[Preheating](https://kean.github.io/post/image-preheating) (prefetching) means loading images ahead of time in anticipation of their use. Nuke provides a `Preheater` class that does just that:

```swift
let preheater = Preheater(manager: Manager.shared)

// User enters the screen:
let requests = [Request(url: url1), Request(url: url2), ...]
preheater.startPreheating(for: requests)

// User leaves the screen:
preheater.stopPreheating(for: requests)
```

You can use Nuke in combination with [Preheat](https://github.com/kean/Preheat) library which automates preheating of content in `UICollectionView` and `UITableView`. With iOS 10.0 you might want to use new [prefetching APIs](https://developer.apple.com/reference/uikit/uitableviewdatasourceprefetching) provided by iOS.

> Check out [Performance Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md) to see what else you can do to improve performance


# Extensions<a name="h_plugins"></a>

|Name|Description|
|--|--|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples of common use cases solved by Rx|
|[**Alamofire**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire) and combine the power of both frameworks|
|[**Gifu**](https://github.com/kean/Nuke-Gifu-Plugin)|Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs|
|[**FLAnimatedImage**](https://github.com/kean/Nuke-AnimatedImage-Plugin)|Use [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) to load and display [animated GIFs]((https://www.youtube.com/watch?v=fEJqQMJrET4))|


# Design<a name="h_design"></a>

Nuke is designed to support [dependency injection](https://en.wikipedia.org/wiki/Dependency_injection). It provides a set of protocols, which can be used to customize image loading pipeline:

|Protocol|Description|
|--------|-----------|
|`Loading`|Loads images|
|`DataLoading`|Downloads data|
|`DataDecoding`|Converts data into image objects|
|`Processing`|Image transformations|
|`Caching`|Stores images into memory cache|

### Data Loading and Caching

A built-in `DataLoader` class implements `DataLoading` protocol and uses [`Foundation.URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) to load image data. The data is cached on disk using a [`Foundation.URLCache`](https://developer.apple.com/reference/foundation/urlcache) instance, which by default is initialized with a memory capacity of 0 MB (Nuke stores images in memory, not image data) and a disk capacity of 150 MB.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) to learn more about image caching

> See [Third Party Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries) guide to learn how to use a custom data loader or cache

Most developers either implement their own networking layer or use a third-party framework. Nuke supports both of those workflows. You can integrate your custom networking layer by implementing `DataLoading` protocol.

> See [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that implements `DataLoading` protocol using [Alamofire](https://github.com/Alamofire/Alamofire) framework

### Memory Cache

Nuke provides a fast in-memory cache (`Cache`) which stores processed images ready to be displayed. `Cache` uses [LRU (least recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm. It has a limit which prevents it from using more than ~20% of available RAM. As a good citizen, `Cache` automatically evicts images on memory warnings and removes most of the images when the application enters background.

# Requirements<a name="h_requirements"></a>

- iOS 9.0 / watchOS 2.0 / macOS 10.11 / tvOS 9.0
- Xcode 9
- Swift 4

# License

Nuke is available under the MIT license. See the LICENSE file for more info.
