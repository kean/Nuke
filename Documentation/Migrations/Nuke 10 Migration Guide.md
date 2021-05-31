# Nuke 10 Migration Guide

This guide eases the transition of the existing apps that use Nuke 9.x to the latest version of the framework.

> To learn about the new features in Nuke 10, see the [release notes](https://github.com/kean/Nuke/releases/tag/10.0.0).

## Minimum Requirements

- iOS 11.0, tvOS 11.0, macOS 10.13, watchOS 4.0
- Xcode 12.0
- Swift 5.3

## Overview

Nuke 10 contains a ton of new features, refinements, and performance improvements. There are some breaking changes and deprecation that the compiler will guide you through as you update. Most users are not going to need this guide.

## loadImage() Signature

The completion callback is now required.

```swift
// Before (Nuke 9)
pipeline.loadImage(with: request)

// After (Nuke 10)
pipeline.loadImage(with: request) { _ in }
```

## Disk Cache Policy

Replace deprecated `DataCacheOptions.storedItems` in the pipeline configuration with [`DataCachePolicy`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Configuration_DataCachePolicy/).

```swift
var configuration = ImagePipeline.Configuration()

// Before (Nuke 9)
configuration.dataCacheOptions.storedItems = [.finalImage]

// After (Nuke 10)
configuration.dataCachePolicy = .storeEncodedImages
```

```swift
// Before (Nuke 9) 
configuration.dataCacheOptions.storedItems = [.originalImageData]

// After (Nuke 10)
configuration.dataCachePolicy = .storeOriginalData
```

```swift
// Before (Nuke 9) 
configuration.dataCacheOptions.storedItems = [.finalImage, .originalImageData]

// After (Nuke 10)
configuration.dataCachePolicy = .storeAll
```

Or use a new [`.automatic`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Configuration_DataCachePolicy/#imagepipeline.configuration.datacachepolicy.automatic) policy if it best fits your needs: for requests with processors, encode and store processed images; for requests with no processors, store original image data. 

> Learn more about the policies and other caching changes in ["Caching: Cache Policy."](https://kean.blog/nuke/guides/caching#cache-policy)

## Disk Cache Configuration

Nuke 10 simplifies disk cache configuration by introducing two built-in configuration: [`ImagePipeline.Configuration.withDataCache`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Configuration/#imagepipeline.configuration.withdatacache) (aggressive disk cache enabled) and [`withURLCache`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Configuration/#imagepipeline.configuration.withurlcache) (HTTP disk cache enabled)

```swift
// Before (Nuke 9)
let dataLoader: DataLoader = {
    let config = URLSessionConfiguration.default
    config.urlCache = nil
    return DataLoader(configuration: config)
}()

var config = ImagePipeline.Configuration()
config.dataLoader = dataLoader
config.dataCache = try? DataCache(name: "com.github.kean.Nuke.DataCache")
```

```swift
// After (Nuke 10)
let config = ImagePipeline.Configuration.withDataCache
```

> Learn more in ["Caching: Configuration."](https://kean.blog/nuke/guides/caching#configuration)

## Direct Access to Cache

In the previous versions, there was no clear way to access underlying cache layers: you could either access each individual layer directly, or use some `ImagePipeline` APIs. Nuke 10 introduces a new cohesive model for working with caches:  [`ImagePipeline.Cache`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Cache/). It has a whole range of convenience APIs for managing cached images: read, write, remove images from all cache layers.

```swift
// Before (Nuke 9) (reading memory cache)
let image = pipeline.cachedImage(for: request)

// After (Nuke 10) (now readwrite)
let image = pipeline.cache[request]
pipeline.cache[request] = image
pipeline.cache[request] = nil
```

```swift
// Before (Nuke 9) (reading disk cache)
let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg")!)
let key = pipeline.cacheKey(for: request, item: .originalImageData)
let data = pipeline.dataCache.cachedData(for: key)

// After (Nuke 10)
let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"))
let data = pipeline.cache.cachedData(for: request)
```

```swift
// New (Nuke 10)
let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"))
let cache = pipeline.cache
let image = cache.cachedImage(for: request) // caches: [.all]
let image = cache.cachedImage(for: request, caches: [.disk])

if cache.containsData(for: request) {
    // ...
}

cache.removeAll()
```

If you still need access to cache keys, [`ImagePipeline.Cache`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Cache/) provides it as well.

```swift
// Before (Nuke 9)
let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"), processors: [ImageProcessors.Resize(width: 44)])
let originalDataKey = pipeline.cacheKey(for: request, item: .originalImageData)
let processedDataKey = pipeline.cacheKey(for: request, item: .finalImage)

// After (Nuke 10)
let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"))
let originalDataKey = pipeline.cache.makeDataCacheKey(for: request)

let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"), processors: [ImageProcessors.Resize(width: 44)])
let processedDataKey = pipeline.cache.makeDataCacheKey(for: request)
```

And you can now also access image (memory) cache keys:

```swift
// New (Nuke 10)
let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"))
let originalDataKey = pipeline.cache.makeImageCacheKey(for: request)
```

> Learn more about the new cache APIs in ["Caching: Direct Access."](https://kean.blog/nuke/guides/caching#direct-access)

## ImageRequestOptions

Nuke 10 has a reworked [`ImageRequest.Options`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageRequest_Options/) option set replacing removed `ImageRequestOptions`. The name is similar, but the options are slightly different. 

```swift
var request = ImageRequest(url: URL(string: "https://example.com/image.jpeg")!)

// Before (Nuke 9)
request.cachePolicy = .reloadIgnoringCachedData
request.options.filteredURL = "example.com/image.jpeg"

// After (Nuke 10)
request.options = [.reloadIgnoringCachedData]
request.userInfo[.imageIdKey] = "example.com/image.jpeg" 
```

`MemoryCacheOptions` are now also part of the same options set.

```swift
// Before (Nuke 9)
request.options.memoryCacheOptions.isReadAllowed = false

// After (Nuke 10)
request.options = [.disableMemoryCacheRead]

// New (Nuke 10)
request.options = [.disableDiskCache]
```

Thanks to these changes, `ImageRequest` now has more options and at the same time uses much less memory (the size reduced from 176 bytes to just 48 bytes).

A deprecated `cacheKey` was a poorly designed option. It was serving a role similar to `filteredURL` but only worked for the memory cache. A better approach is to use the new `.imageIdKey`.

```swift
// Before (Nuke 9)
request.options.cacheKey = "example.com/image.jpeg"

// After (Nuke 10)
request.userInfo[.imageIdKey] = "example.com/image.jpeg"
```

And new in Nuke 10, you can now customize the cache keys using the new [`ImagePipelineDelegate`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipelineDelegate/) protocol.

```swift
// New (Nuke 10)
final class YourImagePipelineDelegate: ImagePipelineDelegate {
    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> ImagePipeline.CacheKey<String> {
        guard let someValue = request.userInfo["someKey"] as? String else {
            return .default
        }
        return .custom(key: someValue)
    }
}
```

And `loadKey` is straight up removed. This API does nothing starting with Nuke 10. If you found an issue with task coalescing, please report it on GitHub and consider disabling it using `ImagePipeline.Configuration`.

## Optional Request

The request in image view extensions is now optional.

```swift
// Before (Nuke 9)
if let url = URL(string: string) {
    Nuke.loadImage(with: url, into: imageView)
} else {
    imageView.image = failureImagePlaceholder
}

// After (Nuke 10)
Nuke.loadImage(with: URL(string: string), into: imageView)
```

If the request is `nil`, it's handled as a failure scenario.

## Extended ImageRequestConvertible

`ImageRequestConvertible` now supports `String` types.

```swift
// Before (Nuke 9)
pipeline.loadImage(with: URL(string: "https://example.com/image.jpeg")!) { _ in }

// New (Nuke 10)
pipeline.loadImage(with: "https://example.com/image.jpeg") { _ in }
```

And, of course, you can still pass `URL` values as usual.

## Animated Images

```swift
// Before (Nuke 9)
configuration.isAnimatedImageDataEnabled = true
let data = response.image.animatedImageData // ObjC associated object

// After (Nuke 10)
let data = response.container.data // Attached automatically for GIFs
```

`Nuke_ImageDisplaying` protocol was also updated: you now receive `data` in the callback that you can use for rendering (data is only attached when needed).  

## ImagePipelineObserving

`ImagePipelineObserving` protocol is now part of the new `ImagePipelineDelegate` protocol.

```swift
// Before (Nuke 9)
let pipeline = ImagePipeline()
pipeline.observer = MockImagePipelineObserver()

class YourImagePipelineObserver: ImagePipelineObserving {
    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent) {
        // ...
    }
}
```

```swift
// After (Nuke 10)
let pipeline = ImagePipeline(delegate: MockImagePipelineObserver())

class YourImagePipelineObserver: ImagePipelineDelegate {
    func pipeline(_ pipeline: ImagePipeline, imageTask: ImageTask, didReceiveEvent event: ImageTaskEvent) {
        // ...
    }
}

ImagePipeline.shared = pipeline // To set the default pipeline
```

---

There are a lot more changes in Nuke 10. You can learn about all of them in the [release notes](https://github.com/kean/Nuke/releases/tag/10.0.0).
