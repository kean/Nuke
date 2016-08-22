<p align="center"><img src="https://cloud.githubusercontent.com/assets/1567433/13918338/f8670eea-ef7f-11e5-814d-f15bdfd6b2c0.png" height="180"/>

<p align="center">
<a href="https://cocoapods.org"><img src="https://img.shields.io/cocoapods/v/Nuke.svg"></a>
<a href="https://github.com/Carthage/Carthage"><img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat"></a>
<a href="http://cocoadocs.org/docsets/Nuke"><img src="https://img.shields.io/cocoapods/p/Nuke.svg?style=flat)"></a>
</p>

Micro-framework for loading, processing, caching and [preheating](https://kean.github.io/blog/image-preheating) images.

## <a name="h_features"></a>Features

- Simple API, zero configuration required
- Performant, asynchronous, thread-safe
- Hassle-free image loading into image views (and other targets)
- Two [cache layers](https://kean.github.io/blog/image-caching) including auto-purging memory cache
- Image transformations
- Automated [preheating (prefetching)](https://kean.github.io/blog/image-preheating)
- [Pipeline](#h_design) with injectable dependencies
- [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin) and [FLAnimatedImage](https://github.com/kean/Nuke-AnimatedImage-Plugin) plugins

## <a name="h_getting_started"></a>Getting Started

- [Homepage](http://kean.github.io/Nuke)
- [Documentation](http://kean.github.io/Nuke/docs/)
- Demo project (`pod try Nuke`)

## <a name="h_usage"></a>Usage

#### Loading Images

Nuke allows for hassle-free image loading into image views (and other arbitrary targets). 

```swift
Nuke.loadImage(with: URL(string: "http://...")!, into: imageView)
```

#### Customizing Requests

Each image request is represented by `Request` struct which can be created with either `URL` or `URLRequest`.

You can add an arbitrary number of image processors to the request. One of the built-in processors is `Decompressor` which [decompresses](https://www.cocoanetics.com/2011/10/avoiding-image-decompression-sickness/) images in the background.

```swift
Nuke.loadImage(with: Request(url: url).process(with: Decompressor()), into: imageView)
```


#### Processing Images

You can specify custom image processors using `Processing` protocol which consists of a single method `process(image: Image) -> Image?`. Here's an example of custom image filter that uses [Core Image](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide):

```swift
struct GaussianBlur: Processing {
    var radius = 8

    func process(image: UIImage) -> UIImage? {
        return image.applyFilter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : self.radius]))
    }

    // `Processing` protocol inherits `Equatable` to identify cached images
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
Loader.shared.loadImage(with: URL(string: "http://...")!, token: cts.token)
    .then { image in print("\(image) loaded") }
    .catch { error in print("catched \(error)") }
```


## Design<a name="h_design"></a>

Nuke is designed to support and leverage dependency injection. It consists of a set of protocols - each with a single responsibility - that come together in an object graph that manages loading, decoding, processing, and caching images. You can easily create and use/inject your own implementations of the following core protocols:

|Protocol|Description|
|--------|-----------|
|`Loading`|Loads images|
|`DataLoading`|Loads data|
|`DataCaching`|Stores data into disk cache|
|`DataDecoding`|Converts data into image objects|
|`Processing`|Image transformations|
|`Caching`|Stores images into memory cache|


## Requirements<a name="h_requirements"></a>

- iOS 9.0 / watchOS 2.0 / macOS 10.11 / tvOS 9.0
- Xcode 8, Swift 3


## Installation<a name="installation"></a>

### [CocoaPods](http://cocoapods.org)

To install Nuke add a dependency to your Podfile:

```ruby
# source 'https://github.com/CocoaPods/Specs.git'
# use_frameworks!

pod "Nuke"
pod "Nuke-Alamofire-Plugin" # optional
pod "Nuke-AnimatedImage-Plugin" # optional
```

### [Carthage](https://github.com/Carthage/Carthage)

To install Nuke add a dependency to your Cartfile:

```
github "kean/Nuke"
github "kean/Nuke-Alamofire-Plugin" # optional
github "kean/Nuke-AnimatedImage-Plugin" # optional
```

## License

Nuke is available under the MIT license. See the LICENSE file for more info.
