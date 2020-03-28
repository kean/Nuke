- [Images are Not Cached](#images-are-not-cached)

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

There are multiple approaches how to solve this issue:

1. Configure the server to return HTTP cache control headers
2. Use custom disk cache, Nuke ships with one:

```swift
ImagePipeline {
    $0.dataCache = try? DataCache(name: "com.myapp.datacache")
}
```

Using `DataCache` has other advantages like significantly improved performance comapred to `Foundation.URLCache`.

