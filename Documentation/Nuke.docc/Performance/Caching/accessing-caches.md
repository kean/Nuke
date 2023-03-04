# Access Cached Images

Learn how to access cached images and data.

## Overview

The pipeline performs cache lookup automatically when you request an image, but you also have a fair deal of control over the caching behavior with ``ImageRequest/Options-swift.struct``.

### Fetching From Cache

If you want to perform cache lookup without download the image from the network, use ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad`` option.

```swift
let request = ImageRequest(url: url, options: [.returnCacheDataDontLoad])
let response = try await pipeline.imageTask(with: request).response
let cacheType = response.cacheType // .memory, .disk, or nil
```

> Important: This option only affects custom cache layers, but not `URLCache`, which is controlled by the [URL loading system](https://developer.apple.com/documentation/foundation/url_loading_system).

### Reloading Images

If you need to reload an image, you can use ``ImagePipeline/Cache-swift.struct`` to remove the image from all cache layers (excluding `URLCache` that reloads automatically based on HTTP cache-control headers) before downloading it.

```swift
let request = ImageRequest(url: url)
pipeline.cache.removeCachedImage(for: request)
```

If you want to keep the image in caches but reload it, you can instruct the pipeline to ignore the cached data.

```swift
let request = ImageRequest(url: url, options: [ .reloadIgnoringCachedData])
let response = try await pipeline.imageTask(with: request).response
```

``ImageRequest/Options-swift.struct`` provides even more granluar control if needed, e.g. ``ImageRequest/Options-swift.struct/disableMemoryCacheReads`` and other similar options.

## Direct Access

You can access any caching layer directly, but the pipeline also offers a convenience API: ``ImagePipeline/Cache-swift.struct``. By using it, you can update multiple cache layers at once, and you don't need to worry about managing the cache keys. It works with custom caches (``ImageCaching`` and ``DataCaching``) but not with `URLCache`, which is controlled by the [URL loading system](https://developer.apple.com/documentation/foundation/url_loading_system).

### Subscript

You can access memory cache with a subscript.

```swift
let image = pipeline.cache[URL(string: "https://example.com/image.jpeg")!]
pipeline.cache[ImageRequest(url: url)] = nil
```

> ``ImageContainer`` contains some metadata about the image, and in the case of animated images or other images that require non-trivial rendering also contains `data`. It also allows you to distinguish between progressive previews in case ``ImagePipeline/Configuration-swift.struct/isStoringPreviewsInMemoryCache`` option is enabled.

All ``ImagePipeline/Cache-swift.struct`` respect request cache control options.

```swift
let url = URL(string: "https://example.com/image.jpeg")!
pipeline.cache[url] = ImageContainer(image: image)

// Returns `nil` because memory cache reads are disabled
let request = ImageRequest(url: url, options: [.disableMemoryCacheWrites])
let image = pipeline.cache[request]
```

### Accessing Images

Apart from the subscript, ``ImagePipeline/Cache-swift.struct`` also has methods for reading and writing images in either memory or disk cache or both.

```swift
let cache = pipeline.cache
let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg")!)

cache.cachedImage(for: request) // From any cache layer
cache.cachedImage(for: request, caches: [.memory]) // Only memory
cache.cachedImage(for: request, caches: [.disk]) // Only disk (decodes data)

let data = cache.cachedData(for: request)
cache.containsData(for: request) // Fast contains check 

// Stores image in the memory cache and stores an encoded
// image in the disk cache
cache.storeCachedImage(ImageContainer(image: image), for: request)

cache.removeCachedImage(for: request)
cache.removeAll()
```

### Managing Cache Keys

You don't need to worry about cache keys when working with ``ImagePipeline/Cache-swift.struct``, but it also gives you access to them in case you need it.

```swift
let request = ImageRequest(url: URL(string: "https://example.com/image.jpeg"))
pipeline.cache.makeImageCacheKey(for: request)
pipeline.cache.makeDataCacheKey(for: request)
```

There is also a hook in ``ImagePipelineDelegate`` that allows you to customize how the keys are generated:

```swift
func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
    request.userInfo["imageId"] as? String
}
```
