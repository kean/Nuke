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
- Deduplication of equivalent requests
- [Pipeline](#h_design) with injectable dependencies
- [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin) and [FLAnimatedImage](https://github.com/kean/Nuke-AnimatedImage-Plugin) plugins

## <a name="h_getting_started"></a>Getting Started

- [Homepage](http://kean.github.io/Nuke)
- [Documentation](http://kean.github.io/Nuke/docs/)
- Demo project (`pod try Nuke`)
- Swift [playground](https://cloud.githubusercontent.com/assets/1567433/10491357/057ac246-72af-11e5-9c60-6f30e0ea9d52.png)

## <a name="h_usage"></a>Usage

#### Loading Images

Nuke allows for hassle-free image loading into image views (and other arbitrary targets). 

```swift
/// Asynchronously fulfills the request into the given target.
/// Cancels previous request started for the target.
Nuke.loadImage(with: URL(string: "http://...")!, into: imageView)
```


#### Customizing Requests

Each request is represented by `Request` struct which can be initialized with either `URL` or `URLRequest`. 

After creating a request you can add an arbitrary number of image processors to it. One of the built-in processors is `Decompressor` which [decompresses](https://www.cocoanetics.com/2011/10/avoiding-image-decompression-sickness/) and (optionally) scales input images.

```swift
let request = Request(url: URL(string: "http://...")!).process(with: Decompressor())
Nuke.loadImage(with: requst, into: imageView)
```


#### Processing Images

Each image processor should conform to `Processing` protocol which consists of a single method `process(image: Image) -> Image?`. Here's an example of custom image filter that uses [Core Image](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide).

```swift
struct GaussianBlur: Processing {
    private let radius: Int
    init(radius: Int = 8) {
        self.radius = radius
    }

    func process(image: UIImage) -> UIImage? {
        return image.applyFilter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : self.radius]))
    }

    // `Processing` protocol inherits `Equatable` to identify cached images, etc.
    func ==(lhs: ImageFilterGaussianBlur, rhs: ImageFilterGaussianBlur) -> Bool {
        return lhs.radius == rhs.radius
    }
}
```


#### Preheating Images

[Preheating](https://kean.github.io/blog/image-preheating) means loading and caching images ahead of time in anticipation of its use. Nuke provides a `Preheater` class with a set of self-explanatory methods for image preheating:

```swift
let preheater = Preheater(loader: Loader.shared)

// User enters the screen:
let requests = [Request(url: imageURL1), Request(url: imageURL2), ...]
preheater.startPreheating(for: requests)

// User leaves the screen:
preheater.stopPreheating(for: requests)
```


#### Automating Preheating

You can use Nuke in combination with [Preheat](https://github.com/kean/Preheat) library which automates preheating of content in `UICollectionView` and `UITableView`. For more info see [Image Preheating Guide](https://kean.github.io/blog/image-preheating), Nuke's demo project, and [Preheat](https://github.com/kean/Preheat) documentation.

```swift
let preheater = Nuke.Preheater(loader: Loader.shared)
let controller = Preheat.Controller(view: <#collectionView#>)
controller.handler = { addedIndexPaths, removedIndexPaths in
    preheater.startPreheating(for: requests(for: addedIndexPaths))
    preheater.stopPreheating(for: requests(for: removedIndexPaths))
}
```


#### Loading Images Directly

One of the core Nuke's classes is `Loader` which manages loading, decoding, processing and caching images. It has a Promise-based API and implementation. You can use it to load images directly:

```swift
let cts = CancellationTokenSource()
Loader.shared.loadImage(with: URL(string: "http://...")!, token: cts.token)
    .then { image in print("\(image) loaded") }
    .catch { error in print("catched \(error)") }
```


## <a name="h_design"></a>Design

Nuke is designed to support and leverage dependency injection. Nuke's core consists of a set of protocols - each with a single responsibility - that come together in an object graph that manages loading, decoding, processing, and caching images. You can easily create and use/inject your own implementations of the following core protocols:

|Protocol|Description|
|--------|-----------|
|`Loading`|A top-level API for loading images|
|`DataLoading`|Loads image data|
|`DataCaching`|Stores data into disk cache|
|`DataDecoding`|Converts data into image objects|
|`Processing`|Image transformations|
|`Caching`|Stores images into memory cache|


## <a name="h_requirements"></a>[Requirements](https://github.com/kean/Nuke/wiki/Supported-Platforms)

- iOS 8.0 / watchOS 2.0 / macOS 10.10 / tvOS 9.0
- Xcode 8, Swift 3


## Installation<a name="installation"></a>

### [CocoaPods](http://cocoapods.org)

To install Nuke add a dependency to your Podfile:

```ruby
# source 'https://github.com/CocoaPods/Specs.git'
# use_frameworks!
# platform :ios, "8.0" / :watchos, "2.0" / :macos, "10.10" / :tvos, "9.0"

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

### Import

Import installed modules in your source files

```swift
import Nuke
import NukeAlamofirePlugin
import NukeAnimatedImagePlugin
```

## <a name="h_satellite_projects"></a>Satellite Projects

- [Preheat](https://github.com/kean/Preheat) - Automates preheating (precaching) of content in UITableView and UICollectionView
- [Nuke Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) - Alamofire plugin for Nuke that allows you to use Alamofire for networking
- [Nuke AnimatedImage Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin) - FLAnimatedImage plugin for Nuke that allows you to load and display animated GIFs

## Contacts

<a href="https://github.com/kean">
<img src="https://cloud.githubusercontent.com/assets/1567433/6521218/9c7e2502-c378-11e4-9431-c7255cf39577.png" height="44" hspace="2"/>
</a>
<a href="https://twitter.com/a_grebenyuk">
<img src="https://cloud.githubusercontent.com/assets/1567433/6521243/fb085da4-c378-11e4-973e-1eeeac4b5ba5.png" height="44" hspace="2"/>
</a>
<a href="https://www.linkedin.com/pub/alexander-grebenyuk/83/b43/3a0">
<img src="https://cloud.githubusercontent.com/assets/1567433/6521256/20247bc2-c379-11e4-8e9e-417123debb8c.png" height="44" hspace="2"/>
</a>

## License

Nuke is available under the MIT license. See the LICENSE file for more info.
