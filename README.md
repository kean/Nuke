<p align="center"><img src="https://cloud.githubusercontent.com/assets/1567433/13918338/f8670eea-ef7f-11e5-814d-f15bdfd6b2c0.png" height="180"/>

<p align="center">
<img src="https://img.shields.io/cocoapods/v/Nuke.svg?label=version">
<img src="https://img.shields.io/badge/supports-CocoaPods%20%7C%20Carthage%20%7C%20SwiftPM-green.svg">
<img src="https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20watchOS%20%7C%20tvOS-lightgrey.svg">
<a href="https://travis-ci.org/kean/Nuke"><img src="https://img.shields.io/travis/kean/Nuke/master.svg"></a>
</p>

A powerful **image loading** and **caching** framework which allows for hassle-free image loading in your app - often in one line of code.

# <a name="h_features"></a>Features

Nuke pulls together **stable**, **mature** libraries from Swift ecosystem into **simple**, **lightweight** package that lets you focus on getting things done.

- Hassle-free image loading into image views and other targets
- Two [cache layers](https://kean.github.io/blog/image-caching) including LRU memory cache
- Extensible image transformations
- [Freedom to use](#h_design) networking, caching libraries of your choice
- Plugins: [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin), [FLAnimatedImage](https://github.com/kean/Nuke-AnimatedImage-Plugin), [Toucan](https://github.com/kean/Nuke-Toucan-Plugin)
- Automated [prefetching](https://kean.github.io/blog/image-preheating) with [Preheat](https://github.com/kean/Preheat) library
- Fast (see [benchmarks](https://github.com/kean/Image-Frameworks-Benchmark)), supports large collection views of images
- Comprehensive test coverage


# <a name="h_getting_started"></a>Quick Start

- [Installation Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Installation%20Guide.md)
- [Wiki](https://github.com/kean/Nuke/blob/master/Documentation/)
- [API Reference](http://cocoadocs.org/docsets/Nuke/4.0/)

Upgrading from the previous version? Use a [migration guide](https://github.com/kean/Nuke/blob/master/Documentation/Migrations).


# <a name="h_usage"></a>Usage

#### Loading Images

Nuke allows for hassle-free image loading into image views and other targets.

```swift
Nuke.loadImage(with: url, into: imageView)
```

#### Reusing Views

`Nuke.loadImage(with:into:)` method cancels previous outstanding request associated with the target. No need to implement `prepareForReuse`. The requests also get cancelled automatically when the target deallocates (Nuke holds a weak reference to a target).

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    Nuke.loadImage(with: url, into: cell.imageView)
}
```

You can also (optionally) implement `collectionView(didEndDisplaying:forItemAt:)` method to cancel the request as soon as the cell goes off screen:

```swift
func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
    Nuke.cancelRequest(for: cell.imageView)
}
```

#### Customizing Requests

Each image request is represented by `Request` struct. It can be created with either `URL` or `URLRequest` and then further customized.

```swift
// Create and customize URLRequest
var urlRequest = URLRequest(url: url)
urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
urlRequest.timeoutInterval = 30

var request = Request(urlRequest: urlRequest)

// You can add arbitrary number of transformations to the request
request.process(with: GaussianBlur())

// Disable memory caching
request.memoryCacheOptions.writeAllowed = false

// Load an image
Nuke.loadImage(with: request, into: imageView)
```

#### Custom Handler

Nuke has a flexible `loadImage(with request: Request, into target: AnyObject, handler: @escaping Handler)` method in which target is a simple reuse token. The method itself doesn't do anything when the image is loaded - you have full control over how to display it, etc. Here's one simple way to use it:

```swift
indicator.startAnimating()
Nuke.loadImage(with: request, into: view) { [weak view] in
    view?.handle(response: $0, isFromMemoryCache: $1)
    indicator.stopAnimating()
}
```

#### Processing Images

You can specify custom image processors using `Processing` protocol which consists of a single method `process(image: Image) -> Image?`. Here's an example of custom image filter that uses [Core Image](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Core%20Image%20Integration%20Guide.md):

```swift
struct GaussianBlur: Processing {
    var radius = 8

    func process(image: UIImage) -> UIImage? {
        return image.applyFilter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : self.radius]))
    }

    // `Processing` protocol requires `Equatable` to identify cached images
    func ==(lhs: GaussianBlur, rhs: GaussianBlur) -> Bool {
        return lhs.radius == rhs.radius
    }
}
```

> See [Toucan plugin](https://github.com/kean/Nuke-Toucan-Plugin) for some useful image transformations

#### Preheating Images

[Preheating](https://kean.github.io/blog/image-preheating) (prefetching) means loading images ahead of time in anticipation of its use. Nuke provides a `Preheater` class that does just that:

```swift
let preheater = Preheater()

// User enters the screen:
let requests = [Request(url: url1), Request(url: url2), ...]
preheater.startPreheating(for: requests)

// User leaves the screen:
preheater.stopPreheating(for: requests)
```


#### Automating Preheating

You can use Nuke in combination with [Preheat](https://github.com/kean/Preheat) library which automates preheating of content in `UICollectionView` and `UITableView`.

```swift
let preheater = Preheater()
let controller = Preheat.Controller(view: collectionView)
controller.handler = { addedIndexPaths, removedIndexPaths in
    preheater.startPreheating(for: requests(for: addedIndexPaths))
    preheater.stopPreheating(for: requests(for: removedIndexPaths))
}
```

> See [Performance Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md) to see what else you can do to improve performance

#### Loading Images Directly

One of the Nuke's core classes is `Loader`. Its API and implementation is based on Promises. You can use it to load images directly.

```swift
let cts = CancellationTokenSource()
Loader.shared.loadImage(with: url, token: cts.token)
    .then { image in print("\(image) loaded") }
    .catch { error in print("catched \(error)") }
```

# Plugins<a name="h_plugins"></a>

### [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin)

Allows you to replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire). Combine the power of both frameworks!

### [FLAnimatedImage Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin)

[FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) plugin allows you to load and display animated GIFs with [smooth scrolling performance](https://www.youtube.com/watch?v=fEJqQMJrET4) and low memory footprint.

### [Toucan Plugin](https://github.com/kean/Nuke-Toucan-Plugin)

[Toucan](https://github.com/gavinbunney/Toucan) plugin provides a simple API for processing images. It supports resizing, cropping, rounded rect masking and more.


# Design<a name="h_design"></a>

Nuke is designed to support [dependency injection](https://en.wikipedia.org/wiki/Dependency_injection). It provides a set of protocols - each with a single responsibility - which manage loading, decoding, processing, and caching images. You can easily create and inject your own implementations of those protocols:

|Protocol|Description|
|--------|-----------|
|`Loading`|Loads images|
|`DataLoading`|Downloads data|
|`DataCaching`|Stores data into disk cache|
|`DataDecoding`|Converts data into image objects|
|`Processing`|Image transformations|
|`Caching`|Stores images into memory cache|

### Data Loading and Caching

Nuke has a basic built-in `DataLoader` class that implements `DataLoading` protocol. It uses [`Foundation.URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) which is a part of the Foundation's [URL Loading System](https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/URLLoadingSystem/URLLoadingSystem.html). Another part of it is [`Foundation.URLCache`](https://developer.apple.com/reference/foundation/urlcache) which provides a composite in-memory and on-disk cache for data. By default it is initialized with a memory capacity of 0 MB (Nuke only stores decompressed images in memory) and a disk capacity of 200 MB.

> See [Image Caching Guide](https://kean.github.io/blog/image-caching) to learn more about URLCache, HTTP caching, and more

Most developers either have their own networking layer, or use some third-party framework. Nuke supports both of these workflows. You can integrate a custom networking layer by implementing `DataLoading` protocol.

> See [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that implements `DataLoading` protocol using [Alamofire](https://github.com/Alamofire/Alamofire) framework

Another useful protocol in Nuke is `DataCaching`. It is used by `CachingDataLoader` which wraps around `DataLoading` object to add a custom cache layer for image data. The main reason to use it is performance. While built-in `Foundation.URLCache` is a great option - it's available out of the box, it's hip to cache control and handles cache revalidation transparently - it might be slow and unpredictable at times.

### Memory Cache

Nuke provides a fast in-memory `Cache` that implements `Caching` protocol. It stores processed images ready to be displayed. `Cache` uses [LRU (least-recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm. By default it is initialized with a memory capacity of 20% of the available RAM. As a good citizen `Cache` automatically evicts images on memory warnings, and removes most of the images when application enters background. 

# Requirements<a name="h_requirements"></a>

- iOS 9.0 / watchOS 2.0 / macOS 10.11 / tvOS 9.0
- Xcode 8
- Swift 3


# License

Nuke is available under the MIT license. See the LICENSE file for more info.
