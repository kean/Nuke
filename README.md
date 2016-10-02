<p align="center"><img src="https://cloud.githubusercontent.com/assets/1567433/13918338/f8670eea-ef7f-11e5-814d-f15bdfd6b2c0.png" height="180"/>

<p align="center">
<a href="https://travis-ci.org/kean/Nuke"><img src="https://img.shields.io/travis/kean/Nuke/master.svg"></a>
<a href="https://github.com/Carthage/Carthage"><img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat"></a>
<a href="https://swift.org/package-manager/"><img src="https://img.shields.io/badge/SPM-ready-orange.svg"></a>
<a href="https://cocoapods.org"><img src="https://img.shields.io/cocoapods/v/Nuke.svg"></a>
<a href="http://cocoadocs.org/docsets/Nuke"><img src="https://img.shields.io/cocoapods/p/Nuke.svg?style=flat)"></a>
</p>

A powerful **image loading** and **caching** framework which allows for hassle-free image loading in your app - often in one line of code.

## <a name="h_features"></a>Features

Nuke pulls together **stable**, **mature** libraries from Swift ecosystem into **simple**, **lightweight** package that lets you focus on getting things done.

- Simple and expressive API, zero configuration required
- Hassle-free image loading into image views and other targets
- Two [cache layers](https://kean.github.io/blog/image-caching) including LRU memory cache
- Extensible image transformations
- [Freedom to use](#h_design) networking, caching libraries of your choice
- Plugins: [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin), [FLAnimatedImage](https://github.com/kean/Nuke-AnimatedImage-Plugin), [Toucan](https://github.com/kean/Nuke-Toucan-Plugin)
- Automated [prefetching](https://kean.github.io/blog/image-preheating) with [Preheat](https://github.com/kean/Preheat) library
- [**Fast**](https://github.com/kean/Image-Frameworks-Benchmark), supports large collection views of images
- Comprehensive test coverage


## <a name="h_getting_started"></a>Getting Started

- [Installation Guide](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Installation%20Guide.md)
- [Wiki](https://github.com/kean/Nuke/blob/master/Documentation/)
- [API Reference](http://cocoadocs.org/docsets/Nuke/4.0/)

Upgrading from the previous version? Use a [migration guide](https://github.com/kean/Nuke/blob/master/Documentation/Migrations).


## <a name="h_usage"></a>Usage

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


#### Loading Images Directly

One of the Nuke's core classes is `Loader`. Its API and implementation is based on Promises. You can use it to load images directly.

```swift
let cts = CancellationTokenSource()
Loader.shared.loadImage(with: url, token: cts.token)
    .then { image in print("\(image) loaded") }
    .catch { error in print("catched \(error)") }
```

## Plugins<a name="h_plugins"></a>

### [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin)

Allows you to replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire). Combine the power of both frameworks!

### [FLAnimatedImage Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin)

[FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) plugin allows you to load and display animated GIFs with [smooth scrolling performance](https://www.youtube.com/watch?v=fEJqQMJrET4) and low memory footprint.

### [Toucan Plugin](https://github.com/kean/Nuke-Toucan-Plugin)

[Toucan](https://github.com/gavinbunney/Toucan) plugin provides a simple API for processing images. It supports resizing, cropping, rounded rect masking and more.


## Design<a name="h_design"></a>

Nuke is designed to support and leverage dependency injection. It consists of a set of protocols - each with a single responsibility - that come together in an object graph that manages loading, decoding, processing, and caching images. You can easily create and use/inject your own implementations of the following core protocols:

|Protocol|Description|
|--------|-----------|
|`Loading`|Loads images|
|`DataLoading`|Downloads data|
|`DataCaching`|Stores data into disk cache|
|`DataDecoding`|Converts data into image objects|
|`Processing`|Image transformations|
|`Caching`|Stores images into memory cache|

You can learn more from an in-depth [Nuke 4 Migration Guide](https://github.com/kean/Nuke/blob/master/Documentation/Migrations/Nuke%204%20Migration%20Guide.md).


## Requirements<a name="h_requirements"></a>

- iOS 9.0 / watchOS 2.0 / macOS 10.11 / tvOS 9.0
- Xcode 8
- Swift 3


## License

Nuke is available under the MIT license. See the LICENSE file for more info.
