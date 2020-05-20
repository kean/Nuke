# Troubleshooting Guide

- [Disk Caching Isn't Working](#disk-caching-isn-t-working)
- [Cached Images are Not Displaying Offline](#cached-images-are-not-displaying-offline)

### Disk Caching Isn't Working

By default, Nuke uses `Foundation.URLCache` which respects HTTP [cache control](https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.9) headers. If the headers are not configured correctly, the images are not going to be stored by `Foundation.URLCache`.

An example of a properly configured HTTP response:

```
HTTP/1.1 200 OK
Cache-Control: public, max-age=3600
Expires: Mon, 26 Jan 2016 17:45:57 GMT
Last-Modified: Mon, 12 Jan 2016 17:45:57 GMT
ETag: "686897696a7c876b7e"
```

> To learn more about HTTP caching, see [Image Caching](https://kean.github.io/post/image-caching)

**Solution**

There are multiple approaches how to solve this issue:

1. Configure the server to return HTTP cache control headers
2. Use custom disk cache which ignores HTTP cache control headers. Nuke already ships with one:

```swift
ImagePipeline {
    $0.dataCache = try? DataCache(name: "com.myapp.datacache")
}
```

> Using `DataCache` has other advantages like significantly improved performance comapred to `Foundation.URLCache`.

### Cached Images are Not Displaying Offline

By default, Nuke uses `Foundation.URLCache` which respects HTTP [cache control](https://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.9) headers. Cache control typically sets an expiration age for each resource. If the resource expires, `URLSession` isn't going to serve it until it goes to the server and _validates_ whether the contents stored in cache are still fresh.

**Solution**

1. Increase the expiration age in HTTP cache control headers
2. Use custom disk cache which ignores HTTP cache control headers. Nuke already ships with one:

 ```swift
 ImagePipeline {
     $0.dataCache = try? DataCache(name: "com.myapp.datacache")
 }
 ```

 > Using `DataCache` has other advantages like significantly improved performance comapred to `Foundation.URLCache`.
 
 3. Force the `URLSession` to return an expired image, and then validate it later in the background. This can easily be done with [ImagePublisher](https://github.com/kean/ImagePublisher#showing-stale-image-while-validating-it) or [RxNuke](https://github.com/kean/RxNuke).
 
 ```swift
 let cacheRequest = URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad)
 let networkRequest = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy)

 let cachedImage = pipeline.imagePublisher(with: ImageRequest(urlRequest: cacheRequest)).orEmpty
 let networkImage = pipeline.imagePublisher(with: ImageRequest(urlRequest: networkRequest)).orEmpty

 cancellable = cachedImage.append(networkImage)
     .sink(receiveCompletion: { _ in /* Ignore errors */ },
           receiveValue: { imageView.image = $0.image })
```

4. Dynamically switch between `.useProtocolCachePolicy` to `.returnCacheDataDontLoad` when network appears to be offline.