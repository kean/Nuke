<p align="center"><img src="https://cloud.githubusercontent.com/assets/1567433/13918338/f8670eea-ef7f-11e5-814d-f15bdfd6b2c0.png" height="180"/>

<p align="center">
<img src="https://img.shields.io/cocoapods/v/Nuke.svg?label=version">
<img src="https://img.shields.io/badge/supports-CocoaPods%20%7C%20Carthage%20%7C%20SwiftPM-green.svg">
<img src="https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-lightgrey.svg">
<a href="https://travis-ci.org/kean/Nuke"><img src="https://img.shields.io/travis/kean/Nuke/master.svg"></a>
</p>

A powerful **image loading** and **caching** framework which allows for hassle-free image loading in your app.

# <a name="h_features"></a>Features

- Load images into image views and other targets
- Two [cache layers](https://kean.github.io/post/image-caching), fast LRU memory cache
- [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin), [Gifu](https://github.com/kean/Nuke-Gifu-Plugin), [Toucan](https://github.com/kean/Nuke-Toucan-Plugin) plugins
- [Freedom to use](#h_design) networking, caching libraries of your choice
- [RxSwift](https://github.com/ReactiveX/RxSwift) extensions provided by [RxNuke](https://github.com/kean/RxNuke)
- Automated [prefetching](https://kean.github.io/post/image-preheating) with [Preheat](https://github.com/kean/Preheat) library
- Simple, small (~1k sloc), [fast](https://github.com/kean/Image-Frameworks-Benchmark) and reliable


# <a name="h_getting_started"></a>Quick Start

- [Installation Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Installation%20Guide.md)
- [Documentation](https://github.com/kean/Nuke/blob/master/Documentation/)
- [API Reference](http://kean.github.io/Nuke/reference/5.1.1/index.html)

Upgrading from the previous version? Use a [migration guide](https://github.com/kean/Nuke/blob/master/Documentation/Migrations).


# <a name="h_usage"></a>Usage

#### Loading Images into Targets

You can load an image into an image view with a single line of code. Nuke will automatically load image data, decompress it in the background, store the image in the memory cache, and finally display it.

```swift
Nuke.loadImage(with: url, into: imageView)
```


#### Reusing Targets

`Nuke.loadImage(with:into:)` method cancels previous outstanding request associated with the target. Nuke holds a weak reference to a target, when the target is deallocated the associated request gets cancelled automatically.

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    ...
    cell.imageView.image = nil
    Nuke.loadImage(with: url, into: cell.imageView)
    ...
}
```

#### Supporting Custom Targets

A `target` can be any class that implements a `Target` protocol: 

```swift
extension UIButton: Nuke.Target {
    func handle(response: Result<Image>, isFromMemoryCache: Bool) {
        setImage(response.value, for: .normal)
    }
}
```


#### Providing Custom Handlers

Nuke also has a flexible `loadImage(with:into:handler:)` method which lets you handle the response by passing a closure:

```swift
indicator.startAnimating()
Nuke.loadImage(with: request, into: view) { [weak view] response, _ in
    view?.image = response.value
    indicator.stopAnimating()
}
```

> The target in this method is declared as `AnyObject` with which the requests get associated. 


#### Customizing Requests

Each request is represented by `Request` struct. A request can be created either with a `URL` or with a `URLRequest`.

```swift
var request = Request(url: url)
// var request = Request(urlRequest: URLRequest(url: url))

// A request has a number of options that you can change:
request.memoryCacheOptions.writeAllowed = false

Nuke.loadImage(with: request, into: imageView)
```


#### Processing Images

Nuke provides an infrastructure for processing images and caching them. You can specify custom image processors using `Processing` protocol which consists of a single method `process(image: Image) -> Image?`:

```swift
struct GaussianBlur: Processing {
    var radius = 8

    func process(image: UIImage) -> UIImage? {
        return image.applyFilter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : self.radius]))
    }

    // `Processing` protocol requires `Equatable` to identify cached images.
    func ==(lhs: GaussianBlur, rhs: GaussianBlur) -> Bool {
        return lhs.radius == rhs.radius // If the processor has no parameters, simply return true
    }
}

// Usage:
let request = Request(url: url).processed(with: GaussianBlur())
Nuke.loadImage(with: request, into: imageView)
```

> See [Core Image Integration Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Core%20Image%20Integration%20Guide.md) for more info about using Core Image with Nuke


#### Using Toucan Plugin

Check out [Toucan Plugin](https://github.com/kean/Nuke-Toucan-Plugin) for some useful image transformations. [Toucan](https://github.com/gavinbunney/Toucan) is a library that provides a clean API for processing images, including resizing, elliptical and rounded rect masking, and more:

```swift
let request = Nuke.Request(url: url).processed(key: "Avatar") { 
    return $0.resize(CGSize(width: 500, height: 500), fitMode: .crop)
             .maskWithEllipse()
}
```


#### Loading Images w/o Targets

You can also use `Manager` to load images directly without providing a target.

```swift
Manager.shared.loadImage(with: url) {
    print("image \($0.value)")
}
```

If you'd like to be able to cancel the requests use a cancellation token:

```swift
let cts = CancellationTokenSource()
Manager.shared.loadImage(with: url, token: cts.token) {
    print("image \($0.value)")
}
cts.cancel()
```


#### Using RxNuke

[RxNuke](https://github.com/kean/RxNuke) adds [RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke and enables many common use cases:

- Going From Low to High Resolution
- Loading the First Available Image
- Showing Stale Image While Validating It
- Load Multiple Images, Display All at Once
- Auto Retry
- Tracking Activities

And [many more...](https://github.com/kean/RxNuke#use-cases)


#### Using Memory Cache

You can get a directly access to the default memory cache used by Nuke:

```swift
Cache.shared.costLimit = 1024 * 1024 * 100 // 100 MB
Cache.shared.countLimit = 100

let request = Request(url: url)
Cache.shared[request] = image
let image = Cache.shared[request]
```


#### Preheating Images

[Preheating](https://kean.github.io/post/image-preheating) (prefetching) means loading images ahead of time in anticipation of its use. Nuke provides a `Preheater` class that does just that:

```swift
let preheater = Preheater(manager: Manager.shared)

// User enters the screen:
let requests = [Request(url: url1), Request(url: url2), ...]
preheater.startPreheating(for: requests)

// User leaves the screen:
preheater.stopPreheating(for: requests)
```

You can use Nuke in combination with [Preheat](https://github.com/kean/Preheat) library which automates preheating of content in `UICollectionView` and `UITableView`. With iOS 10.0 you might want to use new [prefetching APIs](https://developer.apple.com/reference/uikit/uitableviewdatasourceprefetching) provided by iOS.

> See [Performance Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md) to see what else you can do to improve performance


# Plugins<a name="h_plugins"></a>

### [RxNuke](https://github.com/kean/RxNuke)

[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with an examples of common use cases solved by Rx.

### [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin)

Allows you to replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire). Combine the power of both frameworks!

### [Gifu Plugin](https://github.com/kean/Nuke-Gifu-Plugin)

[Gifu](https://github.com/kaishin/Gifu) plugin allows you to load and display animated GIFs.

### [Toucan Plugin](https://github.com/kean/Nuke-Toucan-Plugin)

[Toucan](https://github.com/gavinbunney/Toucan) plugin provides a simple API for processing images. It supports resizing, cropping, rounded rect masking and more.

### [FLAnimatedImage Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin) (Deprecated)

[FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) plugin allows you to load and display animated GIFs with [smooth scrolling performance](https://www.youtube.com/watch?v=fEJqQMJrET4) and low memory footprint.


# Design<a name="h_design"></a>

Nuke is designed to support [dependency injection](https://en.wikipedia.org/wiki/Dependency_injection). It provides a set of protocols - each with a single responsibility - which manage loading, decoding, processing, and caching images. You can easily create and inject your own implementations of those protocols:

|Protocol|Description|
|--------|-----------|
|`Loading`|Loads images|
|`DataLoading`|Downloads data|
|`DataDecoding`|Converts data into image objects|
|`Processing`|Image transformations|
|`Caching`|Stores images into memory cache|

### Data Loading and Caching

Nuke has a basic built-in `DataLoader` class that implements `DataLoading` protocol. It uses [`Foundation.URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) which is a part of the Foundation's [URL Loading System](https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/URLLoadingSystem/URLLoadingSystem.html). Another part of it is [`Foundation.URLCache`](https://developer.apple.com/reference/foundation/urlcache) which provides a composite in-memory and on-disk cache for data. By default it is initialized with a memory capacity of 0 MB (Nuke only stores decompressed images in memory) and a disk capacity of 150 MB.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) to learn more about URLCache, HTTP caching, and more

> If you'd like to use a third-party caching library check out [Third Party Libraries: Using Other Caching Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries)

Most developers either have their own networking layer, or use some third-party framework. Nuke supports both of these workflows. You can integrate a custom networking layer by implementing `DataLoading` protocol.

> See [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that implements `DataLoading` protocol using [Alamofire](https://github.com/Alamofire/Alamofire) framework

> If you'd like to use your own network layer see [Third Party Libraries: Using Other Networking Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-networking-libraries)

### Memory Cache

Nuke provides a fast in-memory `Cache` that implements `Caching` protocol. It stores processed images ready to be displayed. `Cache` uses [LRU (least-recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm. By default it is initialized with a memory capacity of 20% of the available RAM. As a good citizen `Cache` automatically evicts images on memory warnings, and removes most of the images when application enters background.

# Requirements<a name="h_requirements"></a>

- iOS 9.0 / watchOS 2.0 / macOS 10.11 / tvOS 9.0
- Xcode 8, 9
- Swift 3.2 and 4.0


# License

Nuke is available under the MIT license. See the LICENSE file for more info.
