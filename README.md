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
- Extensions for UI components
- Two [cache layers](https://kean.github.io/blog/image-caching) including auto purging memory cache
- Background image decompression
- Custom image filters
- Deduplication of equivalent requests
- Automate [preheating (prefetching)](https://kean.github.io/blog/image-preheating)
- [Pipeline](#h_design) with injectable dependencies
- [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin) and [FLAnimatedImage](https://github.com/kean/Nuke-AnimatedImage-Plugin) plugins

## <a name="h_requirements"></a>[Requirements](https://github.com/kean/Nuke/wiki/Supported-Platforms)

- iOS 8.0 / watchOS 2.0 / OS X 10.10 / tvOS 9.0
- Xcode 8, Swift 3

## <a name="h_getting_started"></a>Getting Started

- Get started at http://kean.github.io/Nuke
- [Documentation](http://kean.github.io/Nuke/docs/)
- Get a demo project using `pod try Nuke`
- Swift [playground](https://cloud.githubusercontent.com/assets/1567433/10491357/057ac246-72af-11e5-9c60-6f30e0ea9d52.png)

## <a name="h_usage"></a>Usage

#### Loading Images

```swift
Nuke.loadImage(with: URL(string: "http://...")!).then { image in
    print("\(image) loaded")
}
```

#### Customizing Requests

Each image request is represented by `Request` struct which can be initialized either with `URL` or `URLRequest`.

```swift
Nuke.loadImage(with: Request(urlRequest: URLRequest(url: (URL: "http://...")!)))
```

#### Using Response

Each of the methods from `loadImage(with:...)` family returns a `Promise<Image>` with expected methods like `then`, `catch`, etc.

```swift
// The closures get called on the main thread by default.
Nuke.loadImage(with: URL(string: "http://...")!)
    .then { image in print("\(image) loaded") }
    .catch { error in print("catched \(error)") }
```

It also has a more conventional in iOS `completion` method:

```swift
Nuke.loadImage(with: URL(string: "http://...")!).completion { resolution in
    switch resolution {
    case let .fulfilled(image): print("\(image) loaded")
    case let .rejected(error): print("catched \(error)") 
    }
}
```

#### Cancelling Request

If you need to cancel your requests you should create them with a [`CancellationToken`](https://msdn.microsoft.com/en-us/library/system.threading.cancellationtokensource(v=vs.110).aspx).
```swift
let cts = CancellationTokenSource()
Nuke.loadImage(with: URL(string: "http://...")!, token: cts.token).then { image in
    print("got \(image)")
}
cts.cancel()
```

This pattern provides a simple and reliable model for cooperative cancellation of asynchronous operations.

#### Using UI Extensions

Nuke provides UI extensions to make image loading as simple as possible.

```swift
let imageView = UIImageView()

// Loads and displays an image for the given URL. Previously started request is cancelled.
imageView.nk_setImage(with: URL(string: "http://...")!)
```

#### Adding UI Extensions

It's also extremely easy to add image loading capabilities (trait) to custom UI components. All you need is to implement `ResponseHandling` protocol in your view which consists of a single method `nk_handle(response:isFromMemoryCache:)`.

```swift
extension MKAnnotationView: ResponseHandling {
    public func nk_handle(response: PromiseResolution<Image>, isFromMemoryCache: Bool) {
        // display image, handle error, etc
    }
}
```

Each view that implements `ResponseHandling` gets a bunch of method for loading images.

```swift
let view = MKAnnotationView()
view.nk_setImage(with: Request(urlRequest: <#request#>))

```

#### Customizing UI Extensions

Each view with image loading trait also get and an associated `ViewContext` object which is your primary interface for customizing image loading.

```swift
let view = UIImageView()
view.nk_context.loader = <#loader#> // `Loader.shared` by default.
view.nk_context.cache = <#cache#> // `Cache.shared` by default.
view.nk_context.handler = { _ in // Overwrite deafult handler.
    // handle the response
}

```

#### UICollection(Table)View

When you display a collection of images it becomes quite tedious to manage tasks associated with image cells. Nuke takes care of all that complexity for you:

```swift
func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCellWithReuseIdentifier(cellReuseID, forIndexPath: indexPath)
    let imageView: ImageView = <#view#>
    imageView.image = nil
    imageView.nk_setImage(with: imageURL)
    return cell
}
```

#### Applying Filters

Nuke defines a simple `Processing` protocol that represents image filters. It takes just a couple line of code to create your own filters. You can apply filters by adding them to the `Request`.

```swift
let filter1: Processing = <#filter#>
let filter2: Processing = <#filter#>

var request = Request(url: <#image_url#>)
request.add(processor: filter1)
request.add(processor: filter2)

Nuke.loadImage(with: request).then { image in
    // do something with a processed image
}.resume()
```

#### Creating Filters

`Processing` protocol consists of a single method `process(image: Image) -> Image?`. Here's an example of custom image filter that uses [Core Image](https://developer.apple.com/library/mac/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_intro/ci_intro.html). For more info see [Core Image Integration Guide](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide).

```swift
struct ImageFilterGaussianBlur: Processing {
    private let radius: Int
    init(radius: Int = 8) {
        self.radius = radius
    }

    func process(image: UIImage) -> UIImage? {
        // The `applyFilter` function is not shipped with Nuke.
        return image.applyFilter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : self.radius]))
    }

    // `Processing` protocol also requires filters to be `Equatable`. 
    // Nuke compares filters to be able to identify cached images and deduplicate equivalent requests.
    func ==(lhs: ImageFilterGaussianBlur, rhs: ImageFilterGaussianBlur) -> Bool {
        return lhs.radius == rhs.radius
    }
}
```

#### Preheating Images

[Preheating](https://kean.github.io/blog/image-preheating) means loading and caching images ahead of time in anticipation of its use. Nuke provides a `Preheater` class with a set of self-explanatory methods for image preheating which were inspired by [PHImageManager](https://developer.apple.com/library/prerelease/ios/documentation/Photos/Reference/PHImageManager_Class/index.html):

```swift
let preheater = Preheater(loader: Loader.shared)

// User enters the screen:
let requests = [Request(url: imageURL1), Request(url: imageURL2), ...]
preheater.startPreheating(for: requests)

// User leaves the screen:
preheater.stopPreheating(for: requests)
```

#### Automating Preheating

You can use Nuke with [Preheat](https://github.com/kean/Preheat) library which automates preheating of content in `UICollectionView` and `UITableView`. For more info see [Image Preheating Guide](https://kean.github.io/blog/image-preheating), Nuke's demo project, and [Preheat](https://github.com/kean/Preheat) documentation.

```swift
let preheater = Nuke.Preheater(loader: Loader.shared)
let controller = Preheat.Controller(view: <#collectionView#>)
controller.handler = { addedIndexPaths, removedIndexPaths in
    preheater.startPreheating(for: requests(for: addedIndexPaths))
    preheater.stopPreheating(for: requests(for: removedIndexPaths))
}
```

#### Caching Images

Nuke provides both on-disk and in-memory caching.

For on-disk caching it relies on `URLCache`. The `URLCache` is used to cache original image data downloaded from the server. This class a part of the URL Loading System's cache management, which relies on HTTP cache.

As an alternative to `URLCache` `Nuke` provides a `DataCaching` protocol that allows you to easily integrate any third-party caching library.

For on-memory caching Nuke provides `Caching` protocol and its implementation in `Cache` class built on top of `Foundation.Cache`. The `Cache` is used for fast access to processed images that are ready for display.

The combination of two cache layers results in a high performance caching system. For more info see [Image Caching Guide](https://kean.github.io/blog/image-caching) which provides a comprehensive look at HTTP cache, URL Loading System and NSCache.

## <a name="h_design"></a>Design

|Protocol|Description|
|--------|-----------|
|`Loading`|A top-level API for loading images|
|`DataLoading`|Performs loading of image data (`Data`)|
|`DataCaching`|Stores data into disk cache (optional)|
|`DataDecoding`|Converts `Data` with `URLResponse` to `Image` objects|
|`Processing`|Processes images (optional)|
|`Caching`|Stores processed images into memory cache|

## Installation<a name="installation"></a>

### [CocoaPods](http://cocoapods.org)

To install Nuke add a dependency to your Podfile:

```ruby
# source 'https://github.com/CocoaPods/Specs.git'
# use_frameworks!
# platform :ios, "8.0" / :watchos, "2.0" / :osx, "10.10" / :tvos, "9.0"

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
