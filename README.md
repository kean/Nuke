<p align="center"><img src="https://cloud.githubusercontent.com/assets/1567433/13918338/f8670eea-ef7f-11e5-814d-f15bdfd6b2c0.png" height="180"/>

<p align="center">
<a href="https://cocoapods.org"><img src="https://img.shields.io/cocoapods/v/Nuke.svg"></a>
<a href="https://github.com/Carthage/Carthage"><img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat"></a>
<a href="http://cocoadocs.org/docsets/Nuke"><img src="https://img.shields.io/cocoapods/p/Nuke.svg?style=flat)"></a>
</p>

Micro-framework for loading, processing, caching and [preheating](https://kean.github.io/blog/image-preheating) images. Get started at http://kean.github.io/Nuke

## <a name="h_features"></a>Features

- Simple, user-friendly API, zero configuration required
- Performant, asynchronous, thread-safe
- Extensions for UI components
- Two [cache layers](https://kean.github.io/blog/image-caching) including auto purging memory cache
- Background image decompression
- Custom image filters
- Deduplication of equivalent requests
- Automate [preheating (precaching)](https://kean.github.io/blog/image-preheating)
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
- [Install](#installation) and `import Nuke`

## <a name="h_usage"></a>Usage

#### Loading Image

Loading an image is as simple as creating and resuming a `Task`. The completion closure is called on the main thread.

```swift
Nuke.loadImage(with: URL(string: "http://...")!) { result in
    let image = result.value
}
```

#### Adding Request Options

Each `Task` is created with an `Request` which contains request parameters. An `Request` can be initialized either with `NSURL` or `NSURLRequest`.

```swift
var request = Request(URLRequest: NSURLRequest(NSURL(URL: "http://...")!))

// Set target size (in pixels) and content mode that describe how to resize loaded image
request.targetSize = CGSize(width: 300.0, height: 400.0)
request.contentMode = .AspectFill

// Set filter (more on filters later)
request.processor = ImageFilterGaussianBlur()

// Control memory caching
request.memoryCacheStorageAllowed = true // true is default
request.memoryCachePolicy = .reloadIgnoringCachedObject // Force reload

// Change the priority of the underlying NSURLSessionTask
request.priority = NSURLSessionTaskPriorityHigh

Nuke.task(with: request) {
    // - Image is resized to fill target size
    // - Blur filter is applied
    let image = $0.image
}.resume()
```

Processed images are stored into memory cache.

#### Using Image Response

The response passed into the completion closure is represented by an `ImageResponse` enum. It has two states: `Success` and `Failure`. Each state has some values associated with it.

```swift
Nuke.task(with: request) { response in
    switch response {
    case let .Success(image, info):
        if (info.isFastResponse) {
            // Image was returned from the memory cache
        }
    case let .Failure(error):
        // Handle error
    }
}.resume()
```

#### Using Image Task

`Task` is your primary interface for controlling the image load. Task is always in one of four states: `Suspended`, `Running`, `Cancelled` or `Completed`. The task is always created in a `Suspended` state. You can use the corresponding `resume()` and `cancel()` methods to control the task's state. It's always safe to call these methods, no matter in which state the task is currently in.

```swift
let task = Nuke.task(with: imageURL).resume()
print(task.state) // Prints "Running"

// Cancels the image load, task completes with an error ImageManagerErrorCode.Cancelled
task.cancel()
```

You can also use `Task` to monitor load progress.

```swift
let task = Nuke.task(with: imageURL).resume()
print(task.progress) // The initial progress is (completed: 0, total: 0)

// Add progress handler which gets called periodically on the main thread
task.progressHandler = { progress in
   // Update progress
}
```

#### Using UI Extensions

Nuke provides UI extensions to make image loading as simple as possible.

```swift
let imageView = UIImageView()

// Loads and displays an image for the given URL
// Previously started requests are cancelled
let task = imageView.nk_setImageWith(NSURL(URL: "http://...")!)
// let task = imageView.nk_setImageWith(Request(...))
```

You have extra control over loading via `ImageViewLoadingOptions`. If allows you to provide custom `animations`, override the completion `handler`, etc.

```swift
let imageView = UIImageView()
let request = Request(URLRequest: NSURLRequest(NSURL(URL: "http://...")!))

var options = ImageViewLoadingOptions()
options.handler = {
    // The `ImageViewLoading` protocol controls the task
    // You handle its completion
}
let task = imageView.nk_setImageWith(request, options: )
```

#### Adding UI Extensions

Nuke makes it extremely easy to add image loading extensions to custom UI components. Those methods are provided by `ImageLoadingView` protocol. This protocol is actually a trait - most of methods are already implemented. All you need is to implement one required method to make your custom views conform to `ImageLoadingView` protocol.

You can do so by either implementing `ImageDisplayingView` protocol:

```swift
extension MKAnnotationView: ImageDisplayingView, ImageLoadingView {
    // That's it, you get default implementation of all methods in ImageLoadingView protocol
    public func nk_displayImage(image: Image?) {
        self.image = image
    }
}
```

Or providing an implementation for remaining `ImageLoadingView` methods:

```swift
extension MKAnnotationView: ImageLoadingView {
    public func nk_Task(task: Task, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions) {
        // Handle task completion
    }
}
```

#### UICollection(Table)View

When you display a collection of images it becomes quite tedious to manage tasks associated with image cells. Nuke takes care of all the complexity for you:

```swift
func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCellWithReuseIdentifier(cellReuseID, forIndexPath: indexPath)
    let imageView: ImageView = <#view#>
    imageView.image = nil
    imageView.nk_setImageWith(imageURL)
    return cell
}
```

#### Applying Filters

Nuke defines a simple `Processing` protocol that represents image filters. It takes just a couple line of code to create your own filters. You can also compose multiple filters together using `ProcessorComposition` class.

```swift
let filter1: Processing = <#filter#>
let filter2: Processing = <#filter#>

var request = Request(url: <#image_url#>)
request.processor = ProcessorComposition(processors: [filter1, filter2])

Nuke.task(with: request) {
    // Filters are applied, processed image is stored into memory cache
    let image = $0.image
}.resume()
```

#### Creating Filters

`Processing` protocol consists of two methods: one to process the image and one to compare two (heterogeneous) filters. Here's an example of custom image filter that uses [Core Image](https://developer.apple.com/library/mac/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_intro/ci_intro.html). For more info see [Core Image Integration Guide](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide).

```swift
public class ImageFilterGaussianBlur: Processing {
    public let radius: Int
    public init(radius: Int = 8) {
        self.radius = radius
    }

    public func process(image: UIImage) -> UIImage? {
        // The `applyFilter` function is not shipped with Nuke.
        return image.applyFilter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : self.radius]))
    }
}

// We need to compare filters to identify cached images
public func ==(lhs: ImageFilterGaussianBlur, rhs: ImageFilterGaussianBlur) -> Bool {
    return lhs.radius == rhs.radius
}
```

#### Preheating Images

[Preheating](https://kean.github.io/blog/image-preheating) means loading and caching images ahead of time in anticipation of its use. Nuke provides a `Preheater` class with a set of self-explanatory methods for image preheating which were inspired by [PHImageManager](https://developer.apple.com/library/prerelease/ios/documentation/Photos/Reference/PHImageManager_Class/index.html):

```swift
let preheater = Preheater(manager: Manager.shared)

// User enters the screen:
let requests = [Request(url: imageURL1), Request(url: imageURL2), ...]
preheater.startPreheating(for: requests)

// User leaves the screen:
preheater.stopPreheating(for: requests)
```

#### Automating Preheating

You can use Nuke with [Preheat](https://github.com/kean/Preheat) library which automates preheating of content in `UICollectionView` and `UITableView`. For more info see [Image Preheating Guide](https://kean.github.io/blog/image-preheating), Nuke's demo project, and [Preheat](https://github.com/kean/Preheat) documentation.

```swift
let preheater = Nuke.Preheater(manager: Manager.shared)
let controller = Preheat.Controller(view: <#collectionView#>)
controller.handler = { addedIndexPaths, removedIndexPaths in
    preheater.startPreheating(for: requests(for: addedIndexPaths))
    preheater.stopPreheating(for: requests(for: removedIndexPaths))
}
```

#### Caching Images

Nuke provides both on-disk and in-memory caching.

For on-disk caching it relies on `NSURLCache`. The `NSURLCache` is used to cache original image data downloaded from the server. This class a part of the URL Loading System's cache management, which relies on HTTP cache.

As an alternative to `NSURLCache` `Nuke` provides an `DataCaching` protocol that allows you to easily integrate any third-party caching library.

For on-memory caching Nuke provides `ImageCaching` protocol and its implementation in `ImageCache` class built on top of `NSCache`. The `ImageCache` is used for fast access to processed images that are ready for display.

The combination of two cache layers results in a high performance caching system. For more info see [Image Caching Guide](https://kean.github.io/blog/image-caching) which provides a comprehensive look at HTTP cache, URL Loading System and NSCache.

#### Accessing Memory Cache

Nuke automatically leverages both its cache layers. It accesses in-memory cache each time you start an `Task`.

If you need to access memory cache directly and synchronously you can use `ImageManager`:

```swift
let manager = ImageManager.shared
let request = Request(url: NSURL(string: "")!)
let response = ImageCachedResponse(image: UIImage(), userInfo: nil)
manager.storeResponse(response, forRequest: request)
let cachedResponse = manager.cachedResponseForRequest(request)
```

`Nuke.task(with: _:)` family of functions are just shortcuts for methods of the `ImageManager` class.

#### Request Deduplication

If you attempt to load an image using `Deduplicator` more than once before the initial load is complete, it would merge duplicate tasks - the image would be loaded only once. In order to enable deduplication you should wrap a `Loading` instance into a `Deduplicator` object. The shared `Manager` uses `Deduplicator` by default.

```swift
let loader = Loader(dataLoader: DataLoader(), dataDecoder: DataDecoder())
let manager = Manager(loader: Deduplicator(loader: loader))
```

#### Customizing Image Manager

 One of the great things about Nuke is that it is [a pipeline](https://github.com/kean/Nuke#h_design) that loads images using injectable dependencies. These protocols are used to customize that pipeline:

|Protocol|Description|
|--------|-----------|
|`DataLoading`|Performs loading of image data (`NSData`)|
|`DataDecoding`|Decodes `NSData` to `UIImage` objects|
|`ImageCaching`|Stores processed images into memory cache|
|`DataCaching`|Stores data into disk cache|

<br>
You can either provide your own implementation of these protocols or customize existing classes that implement them. After you have all the dependencies in place you can create an `ImageManager`:

```swift
let dataLoader: DataLoading = <#dataLoader#>
let decoder: DataDecoding = <#decoder#>
let cache: ImageCaching = <#cache#>

let configuration = ImageManagerConfiguration(dataLoader: dataLoader, decoder: decoder, cache: cache)
ImageManager.shared = ImageManager(configuration: configuration)
```

If even those protocols are not enough, you can take a look at the `ImageLoading` protocol. It provides a high level API for loading images. This protocol is implemented by the `Loader` class that defines a common flow of loading images (`load data` -> `decode` -> `process`) and uses the corresponding `DataLoading`, `DataCaching`, `DataDecoding` and `Processing` protocols.

```swift
let loader: ImageLoading = <#loader#>
let cache: ImageCaching = <#cache#>

// The ImageManagerConfiguration(dataLoader:decoder:cache:) constructor is actually
// just a convenience initializer that creates an instance of Loader class
let configuration = ImageManagerConfiguration(loader: loader, cache: cache)
ImageManager.shared = ImageManager(configuration: configuration)
```

## <a name="h_design"></a>Design

<img src="https://cloud.githubusercontent.com/assets/1567433/9952711/971ae2ea-5de1-11e5-8670-6853d3fe18cd.png" width="66%"/>

|Protocol|Description|
|--------|-----------|
|`ImageManager`|A top-level API for managing images|
|`DataLoading`|Performs loading of image data (`NSData`)|
|`DataDecoding`|Converts `NSData` to `UIImage` objects|
|`Processing`|Processes decoded images|
|`ImageCaching`|Stores processed images into memory cache|
|`DataCaching`|Stores data into disk cache|

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
