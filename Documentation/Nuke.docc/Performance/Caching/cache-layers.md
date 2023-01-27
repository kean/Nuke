# Cache Layers

Learn about memory and disk cache layers in Nuke.

## Overview

Nuke has three cache layers:

- ``ImageCache`` – LRU **memory** cache for processed images
- ``DataCache`` – aggressive LRU **disk** cache
- [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache) – HTTP **disk** cache which is part of the native [URL loading system](https://developer.apple.com/documentation/foundation/url_loading_system)

The default pipeline uses a combination of ``ImageCache`` and [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache) with an increased disk size. This configuration supports HTTP [`cache-control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control). 

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
let urlRequest = URLRequest(url: url)
_ = DataLoader.sharedUrlCache.cachedResponse(for: urlRequest)
DataLoader.sharedUrlCache.removeCachedResponse(for: urlRequest)

// Clear cache
DataLoader.sharedUrlCache.removeAllCachedResponses()
```

An HTTP disk cache (``ImagePipeline/Configuration-swift.struct/withURLCache`` option) gives the server precise control over caching via [`cache-control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) HTTP headers. You can specify what images to cache and for how long. The client can't also periodically check the cached response for [freshness](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching#freshness) and refresh if needed – useful for refreshing profile pictures or logos.

> Tip: Learn more about HTTP cache in ["Image Caching."](https://kean.blog/post/image-caching#http-caching)

#### Serving Stale Images

If the resource expires, `URLSession` isn’t going to serve it until it goes to the server and validates whether the contents stored in the cache are still fresh.

**Solutions**

- Increase the expiration age in HTTP `cache-control` headers
- Use a custom disk cache that ignores HTTP `cache-control` headers
- Ask `URLSession` to return an expired image using [URLRequest.CachePolicy.returnCacheDataDontLoad](https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy/returncachedatadontload) and then validate it later in the background
- Dynamically switch between `.useProtocolCachePolicy` to `.returnCacheDataDontLoad` when network appears to be offline

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

dataCache.sizeLimit = 1024 * 1024 * 100 // 100 MB

// Reduces space usage but adds a slight performance hit
dataCache.isCompressionEnabled = true

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
