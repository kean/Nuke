# Performance Guide

Learn about the performance features in Nuke and how to make the most of them.

## Caching

Images can take a lot of space. By using Nuke, you can ensure that when you download an image, it will be cached so that you don't have to download it again in the future. Nuke provides three different caching layers.

### L1. Memory Cache (Default)

The images are stored in a fast in-memory cache: ``ImageCache``. It uses [LRU (least recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm and has a strict size limit. It also automatically evicts images on memory warnings and removes a portion of its contents when the application enters background mode.

> Important: Nuke stores decompressed (bitmapped) images in the memory cache. If your app is loading and displaying high-resolution images, consider downsampling them and/or increasing cache limits. For context, a bitmap for a 6000x4000px image take 92 MB assuming 4 bytes per pixel.

### L2. HTTP Disk Cache (Default)

By default, unprocessed image data is stored in native [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache), which is part of the [Foundation URL Loading System](https://developer.apple.com/documentation/foundation/url_loading_system). The main feature of `URLCache` is its support of [Cache Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control). Here is an example of an HTTP header with cache control.

```
HTTP/1.1 200 OK
Cache-Control: public, max-age=3600
Expires: Mon, 26 Jan 2016 17:45:57 GMT
Last-Modified: Mon, 12 Jan 2016 17:45:57 GMT
ETag: "686897696a7c876b7e"
```

This response is cacheable and it’s going to be *fresh* for 1 hour. When the response becomes *stale*, the client *validates* it by making a *conditional* request using the `If-Modified-Since` and/or `If-None-Match` headers. If the response is still fresh the server returns status code `304 Not Modified` to instruct the client to use cached data, or it would return `200 OK` with a new data otherwise.

> Tip: Make sure that the images served by the server has [Cache Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) set correctly.

> Important: By default, `URLCache` doesn't serve state images offline. To show a stale image, pass the `URLRequest` with cache policy set to [.returnCacheDataDontLoad](https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy/returncachedatadontload) and then perform a second request to refresh the image.

### L3. Aggressive Disk Cache (Optional)

If your server uses unique URLs for images for which the contents never change, consider enabling ``DataCache`` (see ``ImagePipeline/Configuration-swift.struct/withDataCache`` that also takes care of disabling the default `URLCache`). It's a fast persistent cache with non-blocking writes that allow reads to be parallel to writes and each other. It also works offline and reduces pressure on `URLSession`.

> Tip: By default ``DataCache``, stores only the original image data. To store processed images, use one of the data cache policies that enable it, for example ``ImagePipeline/DataCachePolicy/automatic``.

> Tip: To save disk space see `ImageEncoders.ImageIO` and `ImageEncoder.isHEIFPreferred` option for HEIF support.

## Prefetching

Prefetching means downloading data ahead of time in anticipation of its use. It creates an illusion that the images are simply available the moment you want to see them – no networking involved. It's very effective. See <doc:prefetching> to learn more about how to enable it.

> Important: If you apply processors when displaying final images, make sure to use the same processors for prefetching. Otherwise, Nuke will end-up populating the memory cache with the versions of the images you are never going to need for display.

## Decompression

Image formats often use compression to reduce the overall data size, but it comes at a cost. An image needs to be decompressed, or _bitmapped_, before it can be displayed. `UIImage` does _not_ eagerly decompress this data until you display it. It leads to performance issues like scroll view stuttering. To avoid it, Nuke automatically decompresses the images in the background. Decompression only runs if needed; it won't run for already processed images.

> Note: See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.

## Downsample Images

Ideally, the app should download the images optimized for the target device screen size, but it's not always possible. To reduce the memory usage, downsample the images.

```swift
// Target size is in points
let request = ImageRequest(url: url,  processors: [.resize(width: 320)])
```

> Tip: Some image formats, such as jpeg, can have thumbnails embedded in the original image data. If you are working with a large image and want to show only a thumbnail, consider using ``ImageRequest/ThumbnailOptions``. If the thumbnails aren't available, they are generated. It can be up to 4x faster than using ``ImageProcessors/Resize`` for high-resolution images. 

## Main Thread Performance

Nuke has a whole range of optimizations across the board to make sure it does as little work on the main thread as possible. These optimizations include:

- **CoW**. The primary type in Nuke is ``ImageRequest``. It has multiple options, so the struct is quite large. To make sure that passing it around is as efficient as possible, ``ImageRequest``  uses a Copy-on-Write technique.
- **OptionSet**. In one of the recent version of Nuke, ``ImageRequest`` was optimized even further by using option sets and reordering of properties to take advantage of gaps in memory stride. It currently takes only 48 bytes in memory (compared to 176 bytes in the previous versions).
- **ImageRequest.CacheKey**. Most frameworks use strings to uniquely identify requests. But string manipulations are expensive, this is why in Nuke, there is a special internal type, `ImageRequest.CacheKey`, which allows for efficient equality checks with no strings manipulation.

These are just some examples of the optimization techniques used in Nuke. There are many more. Every new feature in Nuke is designed with performance in mind to make sure there are no performance regressions ever.

> Tip: One thing you can do to optimize the performance on the main thread, is to create URLs in the background as their initialization can be relatively expensive. It's best to do it during decoding. 

## Resumable Downloads

Make sure your server supports resumable downloads. If the data task is terminated when the image is partially loaded (either because of a failure or a cancellation), the next load will resume where the previous left off. Resumable downloads require the server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators: `ETag` and `Last-Modified`. Resumable downloads are enabled by default. You can learn more in ["Resumable Downloads"](https://kean.blog/post/resumable-downloads).

## Coalescing

Thanks to coalescing (enabled by default), the pipeline avoids doing any duplicated work when loading images. Let's take the following two requests as an example.

```swift
let url = URL(string: "http://example.com/image")
pipeline.loadImage(with: ImageRequest(url: url, processors: [
    .resize(size: CGSize(width: 44, height: 44)),
    .gaussianBlur(radius: 8)
]))
pipeline.loadImage(with: ImageRequest(url: url, processors: [
    .resize(size: CGSize(width: 44, height: 44))
]))
```

Nuke will load the data only once, resize the image once and blur it also only once. There is no duplicated work done. When you request an image, the pipeline creates a dependency graph of tasks needed to deliver the final images and reuses the ones that it can.

## Progressive Decoding

Nuke supports progressive JPEG out of the box. You’ll first see a blurry version of the full image, which over time gets sharper as the image is decoded or renders in the app.

## Request Priorities

Nuke is fully asynchronous and performs well under stress. ``ImagePipeline`` distributed its work on [operation queues](https://developer.apple.com/documentation/foundation/operationqueue) dedicated to a specific type of work, such as processing, decoding. Each queue limits the number of concurrent tasks, respects the request priorities, and cancels the work as soon as possible.

Nuke allows you to set the request priority and update it for outstanding tasks. It uses priorities for prefetching: the requests created by the prefetcher all have `.low` priority to make sure they don't interfere with the "regular" requests. See <doc:prefetching> to learn more.

There are many other creative ways to use priorities. For example, when the user taps an image in a grid to open it full screen, you can lower the priority of the requests for the images that are not visible on the screen.

```swift
final class ImageView: UIView {
    private var task: ImageTask?

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)

        task?.priority = newWindow == nil ? .low : .high
    }
}
```

## Rate Limiting

It the app starts and cancels requests a very fast rate, Nuke will rate limit the requests, protecting `URLSession`. `RateLimiter` uses a classic [token bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm. The implementation supports quick bursts of requests which can be executed without any delays when "the bucket is full". This is important to make sure `RateLimiter` only kicks in when needed, but when the user just opens the screen, all of the requests are fired immediately.

## Auto Retry

Enable [`waitsForConnectivity`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/2908812-waitsforconnectivity) on `URLSession` to indicate that the session should wait for connectivity to become available instead of failing the request immediately in case of a network failure.

## Measure

If you want to see how the system behaves, how long each operation takes, and how many are performed in parallel, enable the ``ImagePipeline/Configuration-swift.struct/isSignpostLoggingEnabled`` option and use the `os_signpost` Instrument. For more information see [Apple Documentation: Logging](https://developer.apple.com/documentation/os/logging) and [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/).
