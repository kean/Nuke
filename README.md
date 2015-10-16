<p align="center"><img src="https://cloud.githubusercontent.com/assets/1567433/10440878/a7c6e468-714b-11e5-9b12-baef482c37c1.png" height="100"/>

<p align="center">
<a href="https://cocoapods.org"><img src="https://img.shields.io/cocoapods/v/Nuke.svg"></a>
<a href="https://github.com/Carthage/Carthage"><img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat"></a>
</p>

Advanced pure Swift framework for loading, caching, processing, displaying and preheating images. It uses latest advancements in iOS SDK and doesn't reinvent existing technologies.

Nuke is a [pipeline](#h_design) that loads images using multiple dependencies which can be injected in runtime.

```swift
Nuke.taskWithURL(URL) { 
    let image = $0.image 
}.resume()
```

1. [Getting Started](#h_getting_started)
2. [Usage](#h_usage)
3. [Design](#h_design)
4. [Installation](#installation)
5. [Requirements](#h_requirements)
6. [Satellite Projects](#h_satellite_projects)

## <a name="h_features"></a>Features

- Zero config
- Beautiful [playground](https://cloud.githubusercontent.com/assets/1567433/10491357/057ac246-72af-11e5-9c60-6f30e0ea9d52.png) included
- Performant, asynchronous, thread safe
- Optional [Alamofire plugin](https://github.com/kean/Nuke-Alamofire-Plugin)
- Optional [AnimatedImage plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin)

##### Loading
- Uses [NSURLSession](https://developer.apple.com/library/ios/documentation/Foundation/Reference/NSURLSession_class/) with [HTTP/2](https://en.wikipedia.org/wiki/HTTP/2) support
- Uses a single data task for multiple equivalent requests
- [Automated preheating](https://github.com/kean/Nuke/wiki/Image-Preheating-Guide) of images close to the viewport

##### Caching
- Doesn't reinvent caching, relies on [HTTP cache](https://tools.ietf.org/html/rfc7234) and its implementation in [Foundation](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/URLLoadingSystem/URLLoadingSystem.html)
- Caching is completely transparent to the client
- Two cache layers including [auto purging memory cache](https://github.com/kean/Nuke/wiki/Image-Caching-Guide)

##### Decoding and Processing
- Create and apply image filters
- Background image decompression and scaling in a single step
- Resize loaded images to [fit displayed size](https://developer.apple.com/library/ios/qa/qa1708/_index.html)

##### Advanced
- Compose image filters
- Compose image decoders
- Customize different parts of the framework using dependency injection

## <a name="h_getting_started"></a>Getting Started
- Download the latest [release](https://github.com/kean/Nuke/releases) version
- Experiment with Nuke APIs in a Swift [playground](https://cloud.githubusercontent.com/assets/1567433/10491357/057ac246-72af-11e5-9c60-6f30e0ea9d52.png)
- Take a look at the demo project, it's easy to install with `pod try Nuke` command
- [Install](#installation), `import Nuke` and enjoy!

## <a name="h_usage"></a>Usage

#### Zero Config

```swift
Nuke.taskWithURL(imageURL) {
    let image = $0.image
}.resume()
```

#### Adding Request Options

```swift
var request = ImageRequest(URLRequest: <#NSURLRequest#>)
request.targetSize = CGSize(width: 300.0, height: 400.0) // Set target size in pixels
request.contentMode = .AspectFill

Nuke.taskWithRequest(request) {
    let image = $0.image // Image is resized
}.resume()
```

#### Using Image Response

```swift
Nuke.taskWithRequest(request) { response in
    switch response {
    case let .Success(image, info): 
        // Use image and inspect info
    case let .Failure(error): 
        // Handle error
    }
}.resume()
```

#### Using Image Task

```swift
let task = Nuke.taskWithURL(imageURL).resume()
task.progress = { completed, total in
   // Update progress
}
let state = task.state // Track task state
task.completion { // Add multiple completions, even for completed task
    let image = $0.image
}
task.cancel()
```

#### UICollectionView

```swift
func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCellWithReuseIdentifier(cellReuseID, forIndexPath: indexPath)

    let imageView: ImageView = <#view#>
    imageView.prepareForReuse()
    imageView.setImageWithURL(imageURL)

    return cell
}
```

Cancel image task as soon as the cell goes offscreen (optional):

```swift
func collectionView(collectionView: UICollectionView, didEndDisplayingCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
    let imageView: ImageView = <#view#>
    imageView.prepareForReuse()
}
```

#### Applying Filters

```swift
let filter1: ImageProcessing = <#filter#>
let filter2: ImageProcessing = <#filter#>
let filterComposition = ImageProcessorComposition(processors: [filter1, filter2])

var request = ImageRequest(URL: <#image_url#>)
request.processor = filterComposition

Nuke.taskWithRequest(request) {
    // Filters are applied, filtered image is stored in memory cache
    let image = $0.image
}.resume()
```

#### Composing Image Filters

```swift
let processor1: ImageProcessing = <#processor#>
let processor2: ImageProcessing = <#processor#>
let composition = ImageProcessorComposition(processors: [processor1, processor2])
```

#### Composing Image Decoders

```swift
let decoder1: ImageDecoding = <#decoder#>
let decoder2: ImageDecoding = <#decoder#>
let composition = ImageDecoderComposition(decoders: [decoder1, decoder2])
```

#### Preheating Images

```swift
let requests = [ImageRequest(URL: imageURL1), ImageRequest(URL: imageURL2)]
Nuke.startPreheatingImages(requests: requests)
Nuke.stopPreheatingImages(requests: requests)
```

#### Automate Preheating

```swift
let preheater = ImagePreheatingControllerForCollectionView(collectionView: <#collectionView#>)
preheater.delegate = self // Signals when preheat window changes
```

#### Customizing Image Manager

```swift
let dataLoader: ImageDataLoading = <#dataLoader#>
let decoder: ImageDecoding = <#decoder#>
let cache: ImageMemoryCaching = <#cache#>

let configuration = ImageManagerConfiguration(dataLoader: dataLoader, decoder: decoder, cache: cache)
ImageManager.shared = ImageManager(configuration: configuration)
```

## <a name="h_design"></a>Design

<img src="https://cloud.githubusercontent.com/assets/1567433/9952711/971ae2ea-5de1-11e5-8670-6853d3fe18cd.png" width="66%"/>

|Protocol|Description|
|--------|-----------|
|`ImageManaging`|A high-level API for loading images|
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
# platform :ios, "8.0" / :watchos, "2.0" / :osx, "10.9"

pod "Nuke"
pod "Nuke-Alamofire-Plugin" # optional
pod "Nuke-AnimatedImage-Plugin" # optional
```

### [Carthage](https://github.com/Carthage/Carthage)

To install Nuke add a dependency to your Cartfile:
```
github "kean/Nuke"
github "kean/Nuke-Alamofire-Plugin" # optional
```

### Import

Import installed modules in your source files
```swift
import Nuke
import NukeAlamofirePlugin
import NukeAnimatedImagePlugin
```

## <a name="h_requirements"></a>[Requirements](https://github.com/kean/Nuke/wiki/Supported-Platforms)
- iOS 8.0+ / watchOS 2.0+ / OS X 10.9+
- Xcode 7.0+, Swift 2.0+

## <a name="h_satellite_projects"></a>Satellite Projects

- [Nuke Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) - Alamofire plugin for Nuke that allows you to use Alamofire for networking
- [Nuke AnimatedImage Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin) - FLAnimatedImage plugin for Nuke that allows you to load and display animated GIFs
- [Nuke Integration Tests](https://github.com/kean/Nuke-Integration-Tests) - Contains CocoaPods and Carthage integration tests for Nuke

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
