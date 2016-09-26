# Nuke 4 Migration Guide

Nuke 4 features **Swift 3 compatibility**, and has a lot of improvements both in the API and under the hood. As a major release, it introduces several API-breaking changes.

This guide is provided in order to ease the transition of existing applications using Nuke 3.x to the latest APIs, as well as explain the design and structure of new and changed functionality.

## Requirements

- iOS 9.0, tvOS 9.0, macOS 10.11, watchOS 2.0
- Xcode 8
- Swift 3

> For those of you that would like to use Nuke on iOS 8.0 or macOS 10.9, please use the latest [tagged 3.x release](https://github.com/kean/Nuke/releases) which supports Swift 2.3.

## Overview

Nuke 4 has fully adopted the new **Swift 3** changes and conventions, including the new [API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

Nuke 3 was already a slim framework. Nuke 4 takes it a step further by simplifying almost all of its components.

Here's a few design principles adopted in Nuke 4:

- **Protocol-Oriented Programming.** Nuke 3 promised a lot of customization by providing a set of protocols for loading, caching, transforming images, etc. However, those protocols were vaguely defined and hard to implement in practice. Protocols in Nuke 4 are simple and precise, often consisting of a single method.
- **Single Responsibility Principle.** For example, instead of implementing preheating and deduplicating of equivalent requests in a single vague `ImageManager` class, those features were moved to separate classes (`Preheater`, `Deduplicator`). This makes core classes much easier to reason about.
- **Principle of Least Astonishment**. Nuke 3 had a several excessive protocols, classes and methods which are *all gone* now (`ImageTask`, `ImageManagerConfiguration` just to name a few). Those features are much easier to use now.
- **Simpler Async**. Image loading involves a lot of asynchronous code, managing it was a chore. Nuke 4 adopts two design patterns ([**Promise**](https://github.com/kean/Promise) and **CancellationToken**) that solve most of those problems.

The adoption of those design principles resulted in a simpler, more testable, and more concise code base (which is now under 900 slocs, compared to AlamofireImage's 1426, and Kingfisher's whopping 2357).

I hope that Nuke 4 is going to be a pleasure to use. Thanks for your interest 😄

## New in Nuke 4

### LRU Memory Cache

Nuke 4 features a new custom LRU memory cache which replaced `NSCache`. The primary reason behind this change was the fact that `NSCache` [is not LRU](https://github.com/apple/swift-corelibs-foundation/blob/master/Foundation/NSCache.swift). The new `Nuke.Cache` has some other benefits like better performance, and more control which would enable some new advanced features in future versions.

### Rate Limiter

There is [a known problem](https://github.com/kean/Nuke/issues/59) with `URLSession` that it gets trashed pretty easily when you resume and cancel `URLSessionTasks` at a very high rate (say, scrolling a large collection view with images). Some frameworks combat this problem by simply never cancelling `URLSessionTasks` which are already in `.running` state. This is not an ideal solution, because it forces users to wait for cancelled requests for images which might never appear on the display.

Nuke has a better, classic solution for this problem - it introduces a new `RateLimiter` class which limits the rate at which `URLSessionTasks` are created. `RateLimiter` uses a [token bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm. The implementation supports quick bursts of requests which can be executed without any delays when "the bucket is full". This is important to prevent the rate limiter from affecting "normal" requests flow. `RateLimiter` is enabled by default.

You can see `RateLimiter` in action in a new `Rate Limiter Demo` added in the sample project.

### Toucan Plugin

Make sure to check out new [Toucan plugin](https://github.com/kean/Nuke-Toucan-Plugin) which provides a simple API for processing images. It supports resizing, cropping, rounded rect masking and more.

## Changes in Nuke 4

Almost every API in Nuke has been modified in some way. It's impossible to document every single changes, so here's a list of some of the major and mostly user-visible changes.

### Basics

#### Drop `Image` Prefix

```swift
ImageRequest -> Request
ImageLoading -> Loading
ImageMemoryCaching -> Caching
ImageDataLoading -> DataLoading
ImageDiskCaching -> DataCaching
ImageDecompressor -> DataDecompressor
... etc
```

#### Loading Images into Targets

Instead of adding extensions to UI components Nuke now has a `Manager` class (similar to [Picasso](https://github.com/square/picasso)) which loads images into specific targets (see new `Target` protocol which replaced `ImageLoadingView` and `ImageDisplayingView` protocols).

```swift
// Nuke 3
let request = ImageRequest(URLRequest: NSURLRequest(NSURL(URL: "http://...")!))
imageView.nk_setImageWith(request)

// Nuke 4
let request = Request(urlRequest: URLRequest(url: URL(string: "http://...")!))
Nuke.loadImage(with: request, into: imageView)

// Nuke 4 (NEW)
// Use custom handler, target doesn't have to implement `Target` protocol.
Nuke.loadImage(with: request, into: imageView) { response, isFromMemoryCache in
    // Handle response
}
```

There are many reasons behind the change, just to name a few:

- `Manager` class has context about all the requests per all targets (or just targets per screen if you create a `Manager` per screen). It will allow to add features like: _lower the priority of the requests when the UIVC goes off screen_ - something that works really well in practice.
- `ImageView` no longer "loads images into itself". So Nuke doesn't break MVC.
- No need to prefix methods.
- Nuke 3 had elaborate `ImageLoadingView` and `ImageDisplayingView` protocols. They had lots of methods, some implemented by default, some added in extensions. It was a mess. New `Manager` -> `Target` relation is super simple and feels natural.
- If you want to use custom manager for a specific target you no longer have to inject it anywhere - just use it.

Adding extensions to `UIImageView` that would do something as complicated as loading images is an abuse of extensions. The reason why other frameworks do this is because this is how it was initially implemented in `SDWebImage`.

#### Request

Memory caching options were simplified to a single struct nested in a `Request`.

```swift
// Nuke 3
public enum ImageRequestMemoryCachePolicy {
    case ReturnCachedImageElseLoad
    case ReloadIgnoringCachedImage
}

public struct ImageRequest {
    public var memoryCacheStorageAllowed = true
    public var memoryCachePolicy = ImageRequestMemoryCachePolicy.ReturnCachedImageElseLoad
}

// Nuke 4
public struct Request {
    public struct MemoryCacheOptions {
        public var readAllowed = true
        public var writeAllowed = true
    }
    public var memoryCacheOptions = MemoryCacheOptions()
}
```

Instead of providing a `shouldDecompressImage`, `contentMode`, `targetSize`  property `Request` now simply sets `Decompressor` as a default processor.

```swift
// Nuke 3
public struct ImageRequest {
    public var processor: ImageProcessing?

    public var targetSize: CGSize = ImageMaximumSize
    public var contentMode: ImageContentMode = .AspectFill
    public var shouldDecompressImage = true
}

// Nuke 4
public struct Request {
    public var processor: AnyProcessor? = AnyProcessor(Decompressor())
}
```

Adding processors to the request is now easier.

```swift
// Nuke 4 (NEW)
request.process(with: GaussianBlur())
```

You can now customize cache (used for memory caching) and load (used for deduplicating equivalent requests) keys using `Request`.

```swift
// Nuke 4 (NEW)
public struct Request {
    public var loadKey: AnyHashable?
    public var cacheKey: AnyHashable?
}
```

#### Transformations

`Processing` protocol is now `Equatable`, `func isEquivalent(other: ImageProcessing) -> Bool` was removed. Nuke now uses [type erasure](http://www.russbishop.net/type-erasure) here and in some other places.

```swift
// Nuke 3
public protocol ImageProcessing {
    func process(image: Image) -> Image?
    func isEquivalent(other: ImageProcessing) -> Bool
}

// Nuke 4
public protocol Processing: Equatable {
    func process(_ image: Image) -> Image?
}
```

#### Targets

New `Target` protocol replaced `ImageLoadingView` and `ImageDisplayingView` which had a lot of methods with a default implementation and were very confusing. New protocol on the other hand consists of a single method:

```swift
public protocol Target: class {
    /// Callback that gets called when the request gets completed.
    func handle(response: Response, isFromMemoryCache: Bool)
}
```

#### Preheating

Preheating was moved from `ImageManager` to a separate `Preheater` class. You might create a preheater instance per screen.

```swift
// Nuke 3
let requests = [ImageRequest(URL: imageURL1), ImageRequest(URL: imageURL2)]
Nuke.startPreheatingImages(requests: requests)
Nuke.stopPreheatingImages(requests: requests)

// Nuke 4
let preheater = Preheater()
let requests = [Request(url: url1), Request(url: url2), ...]
preheater.startPreheating(for: requests)
preheater.stopPreheating(for: requests)
```

#### Accessing Memory Cache

You used to have to use `ImageManager` to access memory cache. Now it can be used directly (due to simplified keys management, check out private `Request.Key` if you want to know more).

```swift
// Nuke 3
let manager = ImageManager.shared
let request = ImageRequest(URL: NSURL(string: "")!)
let response = ImageCachedResponse(image: UIImage(), userInfo: nil)
manager.storeResponse(response, forRequest: request)
let cachedResponse = manager.cachedResponseForRequest(request)

// Nuke 4
let cache = Cache.shared
let request = Request(url: URL(string: "")!))
cache[request] = UIImage()
let image = cache[request]
```

### Advanced

#### Loading Images directly

If you do have to load images directly (without using `Manager` and `Target`):

```swift
// Nuke 3
let task = Nuke.taskWith(NSURL(URL: "http://...")!) {
    let image: Image? = $0.image
}
task.resume()
task.cancel()

// Nuke 4
let cts = CancellationTokenSource()
Loader.shared.loadImage(with: URL(string: "http://...")!, token: cts.token)
    .then { image in print("\(image) loaded") }
    .catch { error in print("catched \(error)") }
cts.cancel()
```

#### Redesigned Protocols

Protocols in Nuke 4 are simple and precise, often consisting of a single method.

```swift
// Nuke 4

public protocol Loading {
    func loadImage(with request: Request, token: CancellationToken?) -> Promise<Image>
}

public protocol DataLoading {
    func loadData(with request: URLRequest, token: CancellationToken?) -> Promise<(Data, URLResponse)>
}

public protocol DataCaching {
    func response(for request: URLRequest, token: CancellationToken?) -> Promise<CachedURLResponse>
    func setResponse(_ response: CachedURLResponse, for request: URLRequest)
}

public protocol DataDecoding {
    func decode(data: Data, response: URLResponse) -> Image?
}

public protocol Processing: Equatable {
    func process(_ image: Image) -> Image?
}

public protocol Caching: class {
    subscript(key: AnyHashable) -> Image? { get set }
}
```

#### Adopt AnyHashable

Adopt `AnyHashable` instead of `ImageRequestKey` (which was renamed to `Request.Key` and made private).

## Removed in Nuke 4

### Request Priority

Priority was removed temporary from `Request` because it wasn't performing as good as expected. There should be a better way to implement it.

### Progress Handler

Progress handler was temporary removed from `Request`. I'm still on the fence whether this feature should be included in the framework itself. It might be better handled by notification implemented in a specific `DataLoader`. 

You can always just display an activity indicator instead:

```swift
let indicator = activityIndicator(for: cell)

indicator.startAnimating()
    Nuke.loadImage(with: request, into: imageView) { [weak imageView] in
    imageView?.handle(response: $0, isFromMemoryCache: $1)
    indicator.stopAnimating()
}
```
