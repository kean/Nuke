<p align="center"><img src="https://cloud.githubusercontent.com/assets/1567433/6684993/5971ef08-cc3a-11e4-984c-6769e4931497.png" width="256"/>

Advanced **Swift** framework for loading images. It uses latest features in iOS SDK and doesn't reinvent existing technologies. It has an elegant and powerful API, that you can easily experiment with in the included playground:

![](https://cloud.githubusercontent.com/assets/1567433/6686242/6ae3211c-cc44-11e4-956b-33eb8ed83cab.png)

## Features
- Solid, FSM-based implementation
- Easy to use, yet very powerful API
- Uses latest advancements in [Foundation URL Loading System](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/URLLoadingSystem/URLLoadingSystem.html) including [NSURLSession](https://developer.apple.com/library/ios/documentation/Foundation/Reference/NSURLSession_class/) that supports [SPDY](http://en.wikipedia.org/wiki/SPDY) protocol.
- Instead of reinventing a caching methodology it relies on HTTP cache as defined in [HTTP specification](https://tools.ietf.org/html/rfc7234) and caching implementation provided by [Foundation URL Loading System](https://developer.apple.com/library/mac/documentation/Cocoa/Conceptual/URLLoadingSystem/URLLoadingSystem.html). The caching and revalidation are completely transparent to the client.
- Intelligent image preheating
- Groups similar requests and never executes them twice. Intelligent control over which requests are considered equivalent.
- Unit tested

## Getting Started
- Download the latest version
- Experiment with Nuke APIs in the playground included in the project. Make sure to build framework for simulator before running the playground.

## Requirements
- Xcode 6.3, Swift 1.2
- New Playgrounds
- iOS 8.0

## Usage

#### Create `ImageTask` with `NSURL`, resume task to start the download

```swift
let URL = NSURL(string: "http://...")!
let task = ImageManager.sharedManager().imageTaskWithURL(URL) {
  (image: UIImage?, error: NSError?) -> Void in
  // Use loaded image
}
task.resume()

// You can cancel task at any time
// task.cancel()
```

#### Create `ImageTask` with `ImageRequest`

```swift
var request = ImageRequest(URL: NSURL(string: "http://...")!)
request.targetSize = CGSize(width: 400.0, height: 400.0) // Set target size in pixels
request.contentMode = .AspectFit
request.progressHandler = {
  let progress = $0 // Observe download progress
}

let task = ImageManager.sharedManager().imageTaskWithRequest(request) { 
  (image: UIImage?, error: NSError?) -> Void in
  // Use loaded image
}
task.resume()
```

#### `ImageTask` stores the state of the request

```swift
let task: ImageTask = /* ... */
if task.state == .Completed {
  // Access resulsts of the request at any time
  let image = task.image
  let error = task.error
}
```

#### Preheat images

```swift
let requests = [ImageRequest(URL: /* ... */), ImageRequest(URL: /* ... */)]
let manager = ImageManager.sharedManager()
manager.startPreheatingImages(requests: requests)
manager.stopPreheatingImages()
```

#### Customize `ImageManager`

```swift
// Provide your own NSURLSessionConfiguration
let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
let sessionManager: URLSessionManager = URLSessionManager(sessionConfiguration: sessionConfiguration)

let cache: ImageMemoryCaching = ImageMemoryCache()
let processor: ImageProcessing = ImageProcessor()

let manager = ImageManager(configuration: ImageManagerConfiguration(sessionManager: sessionManager, cache: cache, processor: nil))

// Change shared manager
ImageManager.setSharedManager(manager)
```

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
