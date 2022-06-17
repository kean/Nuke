# Caching

// TODO: Split this into separate files

Nuke has three cache layers that you can configure to precisely match your app needs. The pipeline uses these caches when you request an image. Your app has advanced control over how images are stored and retrieved and direct access to all cache layers.

## Configuration

You have two built-in configurations ``ImagePipeline/Configuration-swift.struct`` to pick from:

- ``ImagePipeline/Configuration-swift.struct/withURLCache`` configuration with a ``DataLoader`` with an HTTP disk cache ([`URLCache`](https://developer.apple.com/documentation/foundation/urlcache)) with a size limit of 150 MB.

- ``ImagePipeline/Configuration-swift.struct/withDataCache`` configuration with an aggressive LRU disk cache ``DataCache`` with a size limit of 150 MB. An HTTP cache is disabled.

Both configurations also have an LRU memory cache ``ImageCache`` enabled and ``ImageCache/shared`` across the pipelines. The size of the memory cache automatically adjusts based on the amount of memory on the device.

The default pipeline uses ``ImagePipeline/Configuration-swift.struct/withURLCache`` configuration by default. You can change the default pipeline by creating a new one:

```swift
ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
```

What configuration should use choose? It depends on your use case.

An **HTTP disk cache** (``ImagePipeline/Configuration-swift.struct/withURLCache`` option) gives the server precise control over caching via [`cache-control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) HTTP headers. You can specify what images to cache and for how long. The client cant also periodically check the cached response for [freshness](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching#freshness) and refresh if needed – useful for refreshing profile pictures or logos.

> Tip: Learn more about HTTP cache in ["Image Caching."](https://kean.blog/post/image-caching#http-caching)

An **aggressive LRU disk cache** (``ImagePipeline/Configuration-swift.struct/withDataCache`` option) ignores HTTP cache-control headers and _always_ stores fetched images, which works great for content that never changes. It can be much faster than `URLCache` in some situations and works great [offline](/nuke/guides/troubleshooting#cached-images-are-not-displaying-offline). Use this option in all situations except when you need HTTP cache control.

### Cache Policy

If you use an aggressive disk cache ``DataCache``, which is a recommended option, you can specify a cache policy ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum``. There are four available options:

| Policy          | Description           |
|---------------|-----------------|
|``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/automatic``|For requests with processors, encode and store processed images. For requests with no processors, store original image data, unless the resource is local (file:// or data:// scheme is used).|
|``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeOriginalData``|For all requests, only store the original image data, unless the resource is local (file:// or data:// scheme is used)|
|``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeEncodedImages``|For all requests, encode and store decoded images after all processors are applied. This is useful if you want to store images in a format different than provided by a server, e.g. decompressed. In other scenarios, consider using .automatic policy instead.|
|``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeAll``|For requests with processors, encode and store processed images. For all requests, store original image data|

The default policy is ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeOriginalData``.

> Important: With ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/automatic`` and ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeEncodedImages`` policies, the pipeline ``ImagePipeline/loadData(with:queue:progress:completion:)`` method will not store the images in the disk cache for requests with any processors applied – this method only loads data and doesn't decode images. This also affects how ``ImagePrefetcher`` with a ``ImagePrefetcher/Destination/diskCache`` destination works.

## Cache Layers

Nuke has three cache layers:

- ``ImageCache`` – LRU **memory** cache for processed images
- ``DataCache`` – aggressive LRU **disk** cache
- [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache) – HTTP **disk** cache which is part of the native [URL loading system](https://developer.apple.com/documentation/foundation/url_loading_system)

If none of the built-in [configurations](#configuration) work for you, you can configure the pipeline to have none, all, or the combination of these cache layers.

### Memory Cache

``ImageCache`` is a **memory** cache with an [LRU cleanup](https://en.wikipedia.org/wiki/Cache_replacement_policies#Least_recently_used_(LRU)) policy (least recently used are removed first). The pipeline uses it to store processed images that are decompressed and are ready to be displayed.

``ImageCache`` discards the least recently cached images if either *cost* or *count* limit is reached. The default cost limit represents a number of bytes and is calculated based on the amount of physical memory available on the device. The default count limit is `Int.max`.

```swift
// Configure cache
ImageCache.shared.costLimit = 1024 * 1024 * 100 // 100 MB
ImageCache.shared.countLimit = 100
ImageCache.shared.ttl = 120 // Invalidate image after 120 sec

// Read and write images
let request = ImageRequest(url: url)
ImageCache.shared[request] = ImageContainer(image: image)
let image = ImageCache.shared[request]

// Clear cache
ImageCache.shared.removeAll()
```

`ImageCache` automatically removes all stored elements when it receives a memory warning. It also automatically removes *most* stored elements when the app enters the background.

> You can implement a custom cache by conforming to the ``ImageCaching`` protocol.

### HTTP Disk Cache

[`URLCache`](https://developer.apple.com/documentation/foundation/urlcache) is an HTTP **disk** cache that is part of the native [URL loading system](https://developer.apple.com/documentation/foundation/url_loading_system). It is used by the default image pipeline which is instantiated with a ``ImagePipeline/Configuration-swift.struct/withURLCache`` configuration.

```swift
// Configure cache
DataLoader.sharedUrlCache.diskCapacity = 100
DataLoader.sharedUrlCache.memoryCapacity = 0

// Read and write responses
let request = ImageRequest(url: url)
let _ = DataLoader.sharedUrlCache.cachedResponse(for: request.urlRequest)
DataLoader.sharedUrlCache.removeCachedResponse(for: request.urlRequest)

// Clear cache
DataLoader.sharedUrlCache.removeAllCachedResponses()
```

An HTTP disk cache (``ImagePipeline/Configuration-swift.struct/withURLCache`` option) gives the server precise control over caching via [`cache-control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) HTTP headers. You can specify what images to cache and for how long. The client cant also periodically check the cached response for [freshness](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching#freshness) and refresh if needed – useful for refreshing profile pictures or logos.

> Tip: Learn more about HTTP cache in ["Image Caching."](https://kean.blog/post/image-caching#http-caching)

### Aggressive Disk Cache

If HTTP caching is not your cup of tea, try a custom LRU disk cache for fast and reliable *aggressive* data caching (ignores [HTTP cache control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)). You can enable it using the respective pipeline configuration.

```swift
ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
```

If you want to change the disk cache configuration, you can also instantiate ``DataCache`` manually or even provide your own implementation by conforming to ``DataCaching`` protocol:

```swift
ImagePipeline {
    $0.dataCache = try? DataCache(name: "com.myapp.datacache")
}
```

> Important: If you enable it manually, make sure to disable the native URL cache. To do it, pass a ``DataLoader`` with a custom `URLSessionConfiguration` when creating a pipeline. Built-in ``ImagePipeline/Configuration-swift.struct/withDataCache`` configuration takes care of it automatically for you.

By default, the pipeline stores only the original image data. You can change this behavior by specifying a different cache policy that was [described earlier](#cache-policy).

```swift
let dataCache = try DataCache(name: "my-cache")

dataCache.sizeLimit = = 1024 * 1024 * 100 // 100 MB

dataCache.storeData(data, for: "key")
if dataCache.containsData(for: "key") {
    print("Data is cached")
}
let data = dataCache.cachedData(for: "key")
// or let data = dataCache["key"]
dataCache.removeData(for: "key")
dataCache.removeAll()
```

``DataCache`` is asynchronous which means ``DataCache/storeData(_:for:)`` method returns imediatelly and the disk I/O happens later. For a syncrhonous write, use ``DataCache/flush()``.

```swift
dataCache.storeData(data, for: "key")
dataCache.flush()
// or dataCache.flush(for: "key")

let url = dataCache.url(for: "key")
// Access file directly
```

## Cache Lookup

The pipeline performs cache lookup automatically when you request an image, but you also have a fair deal of control over the caching behavior with ``ImageRequest/Options-swift.struct``.

### Fetching From Cache

If you want to perform cache lookup without download the image from the network, use ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad`` option.

```swift
let request = ImageRequest(url: url, options: [.returnCacheDataDontLoad])
pipeline.loadImage(with: request) { result in
    switch result {
    case .success(let response):
        let image = response.image
        let cacheType = response.cacheType // .memory, .disk, or nil
    case .failure(let error):
        // Failed with an error
    }
}
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
let request = ImageRequest(url: url, options: [ .reloadIgnoringCacheData])
Nuke.loadImage(with: request, into: imageView)
```

``ImageRequest/Options-swift.struct`` provides even more granluar control if needed, e.g. ``ImageRequest/Options-swift.struct/disableMemoryCacheReads`` and other similar options.

## Direct Access

You can access any caching layer directly, but the pipeline also offers a convenience API: ``ImagePipeline/Cache-swift.struct``. By using it, you can update multiple cache layers at once, and you don't need to worry about managing the cache keys. It works with custom caches (``ImageCaching`` and ``DataCaching``) but not with `URLCache`, which is controlled by the [URL loading system](https://developer.apple.com/documentation/foundation/url_loading_system).

### Subscript

You can access memory cache with a subscript.

```swift
// It works with ImageRequestConvertible so it supports String, URL,
// URLRequest, and ImageRequest
let image = pipeline.cache[URL(string: "https://example.com/image.jpeg")!]
pipeline.cache[ImageRequest(url: url)] = nil
pipeline.cache["https://example.com/image.jpeg"] = ImageContainer(image: image)
```

> ``ImageContainer`` contains some metadata about the image, and in the case of animated images or other images that require non-trivial rendering also contains `data`. It also allows you to distinguish between progressive previews in case ``ImagePipeline/Configuration-swift.struct/isStoringPreviewsInMemoryCache`` option is enabled.

All ``ImagePipeline/Cache-swift.struct`` respect request cache control options.

```swift
let url = URL(string: "https://example.com/image.jpeg")!
pipeline.cache[url] = image

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
cache.storeImage(image, for: request)

cache.removeImage(for: request)
cache.removeAll()
```

### Managing Cache Keys

You don't need to worry about cache keys when working with ``ImagePipeline/Cache-swift.struct``, but it also gives you access to them in case you need it.

```swift
pipeline.cache.makeImageCacheKey(for: request)
pipeline.cache.makeDataCacheKey(for: request)
```

There is also a hook in ``ImagePipelineDelegate`` that allows you to customize how the keys are generated:

```swift
func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
    request.userInfo["imageId"] as? String
}
```

## Topics

### Memory Cache

- ``ImageCaching``
- ``ImageCache``
- ``ImageCacheKey``

### Disk Cache

- ``DataCaching``
- ``DataCache``

### Composite Cache

- ``ImagePipeline/Cache-swift.struct``
