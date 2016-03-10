<p align="left"><img src="https://cloud.githubusercontent.com/assets/1567433/13362579/7001aa94-dcd6-11e5-8c0d-5a4920008d04.png" height="150"/>

<p align="left">
<a href="https://cocoapods.org"><img src="https://img.shields.io/cocoapods/v/Nuke.svg"></a>
<a href="https://github.com/Carthage/Carthage"><img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat"></a>
<a href="http://cocoadocs.org/docsets/Nuke"><img src="https://img.shields.io/cocoapods/p/Nuke.svg?style=flat)"></a>
</p>

Loading, processing, caching and [**preheating**](http://outscope.net/blog/image-preheating) images.

To get started check out http://kean.github.io/Nuke/ !

```swift
var request = ImageRequest(URL: NSURL(string: "http://..."))
request.targetSize = CGSize(width: 200, height: 200) // Resize image
request.processor = ImageFilterGaussianBlur() // Apply image filter

Nuke.taskWith(request) { response in
    let image = response.image
}.resume()
```

## <a name="h_features"></a>Features

- User-friendly API, zero configuration required
- Performant, asynchronous and thread safe
- Nuke is a [pipeline](#h_design) with injectable dependencies
- Optional [Alamofire](https://github.com/kean/Nuke-Alamofire-Plugin) and [AnimatedImage](https://github.com/kean/Nuke-AnimatedImage-Plugin) plugins
- Beautiful [playground](https://cloud.githubusercontent.com/assets/1567433/10491357/057ac246-72af-11e5-9c60-6f30e0ea9d52.png), and [complete documentation](#h_documentation) included

##### Loading

- Uses [NSURLSession](https://developer.apple.com/library/ios/documentation/Foundation/Reference/NSURLSession_class/) with [HTTP/2](https://en.wikipedia.org/wiki/HTTP/2) support
- A single data task is used for multiple equivalent requests
- [Automated preheating](http://outscope.net/blog/image-preheating) of images close to the viewport
- Prevents trashing the system with requests during fast scrolling
- Full featured extensions for UI components

##### Caching

- [Doesn't reinvent caching](http://outscope.net/blog/image-caching), relies on HTTP cache in URL Loading System
- Two cache layers including auto purging memory cache
- Intelligent control over memory cache

##### Processing

- Create, compose and apply image filters
- [Core Image](https://developer.apple.com/library/mac/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_intro/ci_intro.html) integration
- Background image decompression and scaling in a single step
- Resize loaded images to [fit displayed size](https://developer.apple.com/library/ios/qa/qa1708/_index.html)

## <a name="h_requirements"></a>[Requirements](https://github.com/kean/Nuke/wiki/Supported-Platforms)

- iOS 8.0+ / watchOS 2.0+ / OS X 10.9+ / tvOS 9.0+
- Xcode 7.1+, Swift 2.0+

## <a name="h_getting_started"></a>Getting Started

- Best place to get started is http://kean.github.io/Nuke/
- Get a demo project using `pod try Nuke` command
- Experiment with Nuke in a [playground](https://cloud.githubusercontent.com/assets/1567433/10491357/057ac246-72af-11e5-9c60-6f30e0ea9d52.png)
- [Install](#installation), `import Nuke` and enjoy!

## <a name="h_documentation"></a>Documentation

- API reference: [iOS](http://kean.github.io/Nuke/docs/ios/) / [OSX](http://kean.github.io/Nuke/docs/osx/) / [tvOS](http://kean.github.io/Nuke/docs/tvos/) / [watchOS](http://kean.github.io/Nuke/docs/watchos/)
- [Usage](http://kean.github.io/Nuke/usage/)
- [Plugins](http://kean.github.io/Nuke/plugins/)
- [Docs](http://kean.github.io/Nuke/docs/)

## <a name="h_usage"></a>Usage

#### Creating Image Task

Loading an image is as simple as creating and resuming an `ImageTask`. Nuke is thread safe, you can freely create and resume tasks from any thread. The completion closure is called on the main thread.

```swift
Nuke.taskWith(NSURL(URL: "http://...")!) {
    let image = $0.image
}.resume()
```

#### Adding Request Options

Each `ImageTask` object is created with an `ImageRequest` struct which contains request parameters. An `ImageRequest` itself can be initialized either with `NSURL` or `NSURLRequest`.

```swift
var request = ImageRequest(URLRequest: NSURLRequest(NSURL(URL: "http://...")!))

// Set target size (in pixels) and content mode that describe how to resize loaded image
request.targetSize = CGSize(width: 300.0, height: 400.0)
request.contentMode = .AspectFill

// Set filter (more on filters later)
request.processor = ImageFilterGaussianBlur()

// Control memory caching
request.memoryCacheStorageAllowed = true // true is default
request.memoryCachePolicy = .ReloadIgnoringCachedImage // Force reload

// Change the priority of the underlying NSURLSessionTask
request.priority = NSURLSessionTaskPriorityHigh

Nuke.taskWith(request) {
    // - Image is resized to fill target size
    // - Blur filter is applied
    let image = $0.image
}.resume()
```

Processed images are stored into memory cache for fast access. Next time you start the equivalent request the completion closure will be called synchronously.

#### Using Image Response

The response passed into the completion closure is represented by an `ImageResponse` enum. It has two states: `Success` and `Failure`. Each state has some values associated with it.

```swift
Nuke.taskWith(request) { response in
    switch response {
    case let .Success(image, info):
        // Use image and inspect info
        if (info.isFastResponse) {
            // Image was returned from the memory cache
        }
    case let .Failure(error):
        // Handle error
    }
}.resume()
```

#### Using Image Task

`ImageTask` is your primary interface for controlling the image load. Task is always in one of four states: `Suspended`, `Running`, `Cancelled` or `Completed`. The task is always created in a `Suspended` state. You can use the corresponding `resume()` and `cancel()` methods to control the task's state. It's always safe to call these methods, no matter in which state the task is currently in.

```swift
let task = Nuke.taskWith(imageURL).resume()
print(task.state) // Prints "Running"

// Cancels the image load, task completes with an error ImageManagerErrorCode.Cancelled
task.cancel()
```

You can also use `ImageTask` to monitor load progress.

```swift
let task = Nuke.taskWith(imageURL).resume()
print(task.progress) // The initial progress is (completed: 0, total: 0)

// Add progress handler which gets called periodically on the main thread
task.progressHandler = { progress in
   // Update progress
}

// Task represents an image promise
// It allows you to add multiple completion handlers, even when the task is completed
task.completion {
    let image = $0.image
}
```

#### Using UI Extensions

Nuke provides full-featured UI extensions to make image loading as simple as possible.

```swift
let imageView = UIImageView()

// Loads and displays an image for the given URL
// Previously started requests are cancelled
// Uses ImageContentMode.AspectFill and current view size as a target size
let task = imageView.nk_setImageWith(NSURL(URL: "http://...")!)
// let task = imageView.nk_setImageWith(ImageRequest(...))
```

You have some extra control over loading via `ImageViewLoadingOptions`. If allows you to provide custom `animations`, or completely override the completion `handler`.

```swift
let imageView = UIImageView()
let request = ImageRequest(URLRequest: NSURLRequest(NSURL(URL: "http://...")!))

var options = ImageViewLoadingOptions()
options.handler = {
    // The `ImageViewLoading` protocol controls the task
    // You handle its completion
}
let task = imageView.nk_setImageWith(request, options: )
```

#### Adding UI Extensions

Nuke makes it extremely easy to add image loading extensions to custom UI components. Those methods are provided by `ImageLoadingView` protocol. This protocol is actually a trait - most of its methods are already implemented. All you need to do is to implement one required method to make your custom views conform to `ImageLoadingView` protocol.

You can do so by either implementing `ImageDisplayingView` protocol:

```swift
extension MKAnnotationView: ImageDisplayingView, ImageLoadingView {
    // That's it, you get default implementation of all methods in ImageLoadingView protocol
    public var nk_image: UIImage? {
        get { return self.image }
        set { self.image = newValue }
    }
}
```

Or providing an implementation for remaining `ImageLoadingView` methods:

```swift
extension MKAnnotationView: ImageLoadingView {
    public func nk_imageTask(task: ImageTask, didFinishWithResponse response: ImageResponse, options: ImageViewLoadingOptions) {
        // Handle task completion
    }
}
```

#### UICollection(Table)View

Sometimes you need to display a collection of images, which is a quite complex task when it comes to managing which tasks are associated with which cells, cancelling and handling those tasks, etc. Nuke takes care of all the complexity for you:

```swift
func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCellWithReuseIdentifier(cellReuseID, forIndexPath: indexPath)
    let imageView: ImageView = <#view#>
    imageView.image = nil
    imageView.nk_setImageWith(imageURL)
    return cell
}
```

Optional: you can also cancel image tasks as soon as the cells go offscreen:

```swift
func collectionView(collectionView: UICollectionView, didEndDisplayingCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
    let imageView: ImageView = <#view#>
    imageView.nk_cancelLoading()
}
```

#### Applying Filters

Nuke defines a simple `ImageProcessing` protocol that represents image filters. Some filters are already built into the framework. And it task just a couple line of code to create your own filters. You can also compose multiple filters together using `ImageProcessorComposition` class.

```swift
let filter1: ImageProcessing = <#filter#>
let filter2: ImageProcessing = <#filter#>

var request = ImageRequest(URL: <#image_url#>)
request.processor = ImageProcessorComposition(processors: [filter1, filter2])

Nuke.taskWith(request) {
    // Filters are applied, processed image is stored into memory cache
    let image = $0.image
}.resume()
```

#### Creating Filters

`ImageProcessing` protocol consists of two methods: one to process the image and one to compare two (heterogeneous) filters. Here's an example of custom image filter implemented on top of [Core Image](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide). It uses some of the helper functions provided by Nuke that simplify work with `Core Image`.

```swift
public class ImageFilterGaussianBlur: ImageProcessing {
    public let radius: Int
    public init(radius: Int = 8) {
        self.radius = radius
    }

    public func process(image: UIImage) -> UIImage? {
        return image.nk_filter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : self.radius]))
    }
}

// We need to be able to compare filters for equivalence to cache processed images
// Default implementation returns `true` if both filters are of the same class
public func ==(lhs: ImageFilterGaussianBlur, rhs: ImageFilterGaussianBlur) -> Bool {
    return lhs.radius == rhs.radius
}
```

#### Preheating Images

[Preheating](http://kean.github.io/blog/programming/2015/12/12/image-preheating.html) is an effective way to improve user experience in applications that display collections of images. Preheating means loading and caching images that might soon appear on the display. Nuke provides a set of self-explanatory methods for image preheating which are inspired by [PHImageManager](https://developer.apple.com/library/prerelease/ios/documentation/Photos/Reference/PHImageManager_Class/index.html):

```swift
let requests = [ImageRequest(URL: imageURL1), ImageRequest(URL: imageURL2)]
Nuke.startPreheatingImages(requests: requests)
Nuke.stopPreheatingImages(requests: requests)
```

#### Automating Preheating

Nuke automates a process of determining which images in a `UICollectionView` (or `UITableView`) to preheat and when to start and stop preheating them. There are two corresponding classes (one for `UICollectionView`, one for `UITableView`). For more info about them see [Image Preheating Guide](http://kean.github.io/blog/programming/2015/12/12/image-preheating.html).

```swift
let preheater = ImagePreheatingControllerForCollectionView(collectionView: <#collectionView#>)
preheater.delegate = self // Signals when preheat index paths change
```

#### Caching Images

Nuke provides both on-disk and in-memory caching.

For on-disk caching it relies on `NSURLCache`. The `NSURLCache` is used to cache original image data downloaded from the server. This class a part of the URL Loading System's cache management, which relies on HTTP cache.

For on-memory caching Nuke provides `ImageMemoryCaching` protocol and its implementation in `ImageMemoryCache` class built on top of `NSCache`. The `ImageMemoryCache` is used for fast access to processed images that are ready for display.

The combination of two cache layers results in a high performance caching system. For more info see [Image Caching Guide](http://outscope.net/blog/image-caching) which provides a comprehensive look at HTTP cache, URL Loading System and NSCache.

#### Accessing Memory Cache

Nuke automatically leverages both its cache layers. It accesses in-memory cache each time you start an `ImageTask` and calls a completion closure synchronously if the appropriate image is found.

If you need to access memory cache directly you might use the appropriate `ImageManager` methods:

```swift
let manager = ImageManager.shared
let request = ImageRequest(URL: NSURL(string: "")!)
let response = ImageCachedResponse(image: UIImage(), userInfo: nil)
manager.storeResponse(response, forRequest: request)
let cachedResponse = manager.cachedResponseForRequest(request)
```

`Nuke.taskWith(_:)` family of functions are just shortcuts for methods of the `ImageManager` class.

#### Customizing Image Manager

 One of the great things about Nuke is that it is [a pipeline](https://github.com/kean/Nuke#h_design) that loads images using injectable dependencies. There are there protocols that you can use to customize that pipeline:

|Protocol|Description|
|--------|-----------|
|`ImageDataLoading`|Performs loading of image data (`NSData`)|
|`ImageDecoding`|Decodes `NSData` to `UIImage` objects|
|`ImageMemoryCaching`|Stores processed images into memory cache|

<br>
You can either provide your own implementation of these protocols or customize existing classes that implement them. After you have all the dependencies in place you can create an `ImageManager`:

```swift
let dataLoader: ImageDataLoading = <#dataLoader#>
let decoder: ImageDecoding = <#decoder#>
let cache: ImageMemoryCaching = <#cache#>

let configuration = ImageManagerConfiguration(dataLoader: dataLoader, decoder: decoder, cache: cache)
ImageManager.shared = ImageManager(configuration: configuration)
```

Even if those protocols are not enough, you can take a look at the `ImageLoading` protocol. It provides a high level API for loading images for concrete `ImageTasks`. This protocol is implemented by the `ImageLoader` class that defines a common flow of loading images (`load data` -> `decode` -> `process`) and uses the corresponding `ImageDataLoading`, `ImageDecoding` and `ImageProcessing` protocols.

```swift
let loader: ImageLoading = <#loader#>
let cache: ImageMemoryCaching = <#cache#>

// The ImageManagerConfiguration(dataLoader:decoder:cache:) constructor is actually
// just a convenience initializer that creates an instance of ImageLoader class
let configuration = ImageManagerConfiguration(loader: loader, cache: cache)
ImageManager.shared = ImageManager(configuration: configuration)
```

## <a name="h_design"></a>Design

<img src="https://cloud.githubusercontent.com/assets/1567433/9952711/971ae2ea-5de1-11e5-8670-6853d3fe18cd.png" width="66%"/>

|Protocol|Description|
|--------|-----------|
|`ImageManager`|A top-level API for managing images|
|`ImageDataLoading`|Performs loading of image data (`NSData`)|
|`ImageDecoding`|Converts `NSData` to `UIImage` objects|
|`ImageProcessing`|Processes decoded images|
|`ImageMemoryCaching`|Stores processed images into memory cache|

## Installation<a name="installation"></a>

### [CocoaPods](http://cocoapods.org)

To install Nuke add a dependency to your Podfile:

```ruby
# source 'https://github.com/CocoaPods/Specs.git'
# use_frameworks!
# platform :ios, "8.0" / :watchos, "2.0" / :osx, "10.9" / :tvos, "9.0"

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

- [Nuke Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) - Alamofire plugin for Nuke that allows you to use Alamofire for networking
- [Nuke AnimatedImage Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin) - FLAnimatedImage plugin for Nuke that allows you to load and display animated GIFs
- [Nuke Integration Tests](https://github.com/kean/Nuke-Integration-Tests) - Contains CocoaPods and Carthage integration tests for Nuke

## <a name="h_donations"></a>Donations

This project has taken hundreds hours of work. If you find it useful, you can chip in for coffee to keep me going.

<a href="https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=B257REANNAAL6"><img height="30" src="https://cloud.githubusercontent.com/assets/1567433/12656493/a1b6075c-c60f-11e5-85a7-0f0c4dea27ed.gif"></a>

> *Alternatively, <a href="https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=8VLXL699RFRY2">donate in ₽*</a>

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
