# Performance Guide

Learn about the performance features and how to make the most of them.

## Caching

Images can take a lot of space. When you download an image, it gets cached so that you don't have to download it again. There are three different caching layers.

### L1. Memory Cache (Default)

The images are stored in a fast in-memory cache: ``ImageCache``. It uses [LRU (least recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm and has a strict size limit. It also automatically evicts images on memory warnings and removes a portion of its contents when the application enters background mode.

> Important: The memory cache stores decompressed (bitmapped) images. If your app is loading and displaying high-resolution images, consider downsampling them and/or increasing cache limits. For context, a bitmap for a 6000x4000px image takes 92 MB (assuming it needs 4 bytes per pixel).

### L2. HTTP Disk Cache (Default)

By default, unprocessed image data is stored in native [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache), which is part of the [Foundation URL Loading System](https://developer.apple.com/documentation/foundation/url_loading_system). The main feature of `URLCache` is its support of [Cache Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control). Here is an example of an HTTP header with cache control.

```
HTTP/1.1 200 OK
Cache-Control: public, max-age=3600
Expires: Mon, 26 Jan 2016 17:45:57 GMT
Last-Modified: Mon, 12 Jan 2016 17:45:57 GMT
ETag: "686897696a7c876b7e"
```

This response is cacheable, and will be *fresh* for 1 hour. When the response becomes *stale*, the client *validates* it by making a *conditional* request using the `If-Modified-Since` and/or `If-None-Match` headers. If the response is still fresh, the server returns status code `304 Not Modified` to instruct the client to use cached data, or it would return `200 OK` with new data otherwise.

> Tip: Make sure that the images served by the server have [Cache Control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) set correctly.

> Important: By default, `URLCache` doesn't serve stale images offline. To show a stale image, pass the `URLRequest` with cache policy set to [.returnCacheDataDontLoad](https://developer.apple.com/documentation/foundation/nsurlrequest/cachepolicy/returncachedatadontload) and then perform a second request to refresh the image.

### L3. Aggressive Disk Cache (Optional)

If your server uses unique URLs for images for which the contents never change, consider enabling ``DataCache`` (see ``ImagePipeline/Configuration-swift.struct/withDataCache`` that also takes care of disabling the default `URLCache`). It's a fast persistent cache with non-blocking writes that allows reads to be parallel to writes and each other. It also works offline and reduces pressure on `URLSession`.

> Tip: By default, ``DataCache`` stores only the original image data (``ImagePipeline/DataCachePolicy/storeOriginalData``). To also cache processed images, set ``ImagePipeline/Configuration-swift.struct/dataCachePolicy`` on the configuration. ``ImagePipeline/DataCachePolicy/automatic`` is a good default: it stores original data for unprocessed requests and processed images for requests with processors.

```swift
var configuration = ImagePipeline.Configuration.withDataCache()
configuration.dataCachePolicy = .automatic

ImagePipeline.shared = ImagePipeline(configuration: configuration)
```

> Tip: To save disk space, see `ImageEncoders.ImageIO` and `ImageEncoder.isHEIFPreferred` option for HEIF support.

## Prefetching

Prefetching means downloading data ahead of time in anticipation of its use. It creates an illusion that the images are simply available the moment you want to see them – no networking involved. It's very effective. See <doc:prefetching> to learn more about how to enable it.

> Important: If you apply processors when displaying final images, make sure to use the same processors for prefetching. Otherwise, the prefetcher will end up populating the memory cache with the versions of the images you are never going to need for display.

## Decompression

Image formats often use compression to reduce the overall data size, but it comes at a cost. An image needs to be decompressed, or _bitmapped_, before it can be displayed. `UIImage` does _not_ eagerly decompress this data until you display it. It leads to performance issues like scroll view stuttering. To avoid it, the pipeline automatically decompresses the images in the background. Decompression only runs if needed; it won't run for already processed images.

> Note: See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.

## Downsample Images

Ideally, the app should download the images optimized for the target device screen size, but it's not always possible. To reduce memory usage, downsample the images.

```swift
// Target size is in points
let request = ImageRequest(url: url, processors: [.resize(width: 320)])
```

> Tip: Some image formats, such as jpeg, can have thumbnails embedded in the original image data. If you are working with a large image and want to show only a thumbnail, consider using ``ImageRequest/ThumbnailOptions``. If the thumbnails aren't available, they are generated. It can be up to 4x faster than using ``ImageProcessors/Resize`` for high-resolution images. 

## Main Thread Performance

The framework has a range of optimizations across the board to ensure it does as little work on the main thread as possible.

- **CoW**. The primary type is ``ImageRequest``. It has multiple options, so the struct is quite large. To make sure that passing it around is as efficient as possible, ``ImageRequest``  uses a Copy-on-Write technique.
- **OptionSet**. In one of the recent versions, ``ImageRequest`` was optimized even further by using option sets and reordering properties to take advantage of gaps in memory stride to reduce its memory layout.
- **ImageRequest.CacheKey**. Most frameworks use strings to uniquely identify requests. But string manipulations are expensive, and this is why there is a special internal type, `ImageRequest.CacheKey`, which allows for efficient equality checks with no strings manipulation.

These are just some examples of the optimization techniques used. There are many more. Every new feature is designed with performance in mind to make sure there are no performance regressions ever.

> Tip: One thing you can do to optimize the main thread's performance is create URLs in the background, as their initialization can be relatively expensive. It's best to do it during decoding.  

## Resumable Downloads

Make sure your server supports resumable downloads. If the data task is terminated when the image is partially loaded (either because of a failure or a cancellation), the next load will resume where the previous one left off. Resumable downloads require the server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Both validators are supported: `ETag` and `Last-Modified`. Resumable downloads are enabled by default. You can learn more in ["Resumable Downloads"](https://kean.blog/post/resumable-downloads).

## Coalescing

Thanks to coalescing (enabled by default), the pipeline avoids doing any duplicated work when loading images. Let's take the following two requests as an example.

```swift
let url = URL(string: "https://example.com/image")

// Only one network request is made for both of these
let blurred = pipeline.imageTask(with: ImageRequest(url: url, processors: [
    .resize(size: CGSize(width: 44, height: 44)),
    .gaussianBlur(radius: 8)
]))
let thumbnail = pipeline.imageTask(with: ImageRequest(url: url, processors: [
    .resize(size: CGSize(width: 44, height: 44))
]))
```

The pipeline will load the data only once, resize the image once and blur it also only once. There is no duplicated work done. When you request an image, the pipeline creates a dependency graph of tasks needed to deliver the final images and reuses the ones that it can.

> Note: Coalescing is controlled by ``ImagePipeline/Configuration-swift.struct/isTaskCoalescingEnabled``. It can be disabled if you need requests with the same URL to be treated as independent tasks.

## Progressive Decoding

Progressive JPEG is supported, but it must be enabled in the pipeline configuration.

```swift
ImagePipeline.shared = ImagePipeline {
    $0.isProgressiveDecodingEnabled = true
}
```

Once enabled, you’ll first see a blurry low-quality version of the full image, which gets sharper as more data arrives. Progressive previews are delivered through the same ``ImageTask`` progress handler or `AsyncStream` used for the final image.

## Request Priorities

Image loading is fully asynchronous and performs well under stress. ``ImagePipeline`` distributes its work on ``TaskQueue`` instances dedicated to a specific type of work, such as processing and decoding. Each queue limits the number of concurrent tasks, respects the request priorities, and cancels the work as soon as possible.

Cancelling an ``ImageTask`` frees its associated network and CPU resources immediately. Thanks to coalescing, the underlying work is only cancelled when all requests sharing it have been cancelled — so cancelling one request doesn't affect others loading the same image.

You can set the request priority and update it for outstanding tasks. Priorities are also used for prefetching: the requests created by the prefetcher all have `.low` priority to make sure they don't interfere with the "regular" requests. See <doc:prefetching> to learn more.

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

If the app starts and cancels requests at a fast rate, the pipeline will rate limit the requests, protecting `URLSession`. `RateLimiter` uses a classic [token bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm. The implementation supports quick bursts of requests which can be executed without any delays when "the bucket is full". It is important to make sure `RateLimiter` only kicks in when needed, but when the user opens the screen, all the requests are fired immediately.

## Auto Retry

Enable [`waitsForConnectivity`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/2908812-waitsforconnectivity) on `URLSession` to indicate that the session should wait for connectivity to become available instead of failing the request immediately in case of a network failure.

## Measure

If you want to see how the system behaves, how long each operation takes, and how many are performed in parallel, enable the ``ImagePipeline/Configuration-swift.struct/isSignpostLoggingEnabled`` option and use the `os_signpost` Instrument. For more information, see [Apple Documentation: Logging](https://developer.apple.com/documentation/os/logging) and [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/).

To collect the same information in a shipping app, enable ``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled``. Every task then finishes with an ``ImageTask/Metrics`` record: where the image came from, how long each stage took and how long it waited for a queue, what the download cost, and whether another task shared the work. The record is `Codable`, and its `description` is a text timeline of the load.

```swift
let pipeline = ImagePipeline {
    $0.isDiagnosticsEnabled = true
}

let task = pipeline.imageTask(with: url)
let image = try await task.image
print(task.metrics!)
```

The print is the record in full: a header, one line that says where the time went, and the tree of the work the task waited on – with the requests `URLSession` made nested under the download that made them. Here is a task from a feed, resizing an image that a prefetcher had started fetching 130 ms earlier:

```
ImageTask #2 "feed" · success · 225.4 ms · from network
url:         https://cdn.example.com/photos/1024.jpg
processors:  com.github.kean/nuke/resize?s=(300.0, 300.0),cm=.aspectFill,crop=false,upscale=false
priority:    normal
image:       450×300 · jpeg · 540 KB in memory
transfer:    325 KB
coalesced:   yes · shared with #1 (j1, j2, j3)
pipeline:    F7DE81F8
time:        network 168.4 ms (75%) · decompress 26.3 ms (12%) · decode 17.8 ms (8%) · process 4.4 ms (2%) · queue 0.6 ms · cache 0.3 ms · other 7.6 ms (3%)

pending                          1.2 ms  ▏                      1%  started at 16:12:58.716
j4 loadImage [resize]          224.2 ms  ████████████████████  99%
├─ memoryLookup                 <0.1 ms  ▏                          miss · key a71c34e2
├─ diskLookup                    0.1 ms  ▏                          miss · key 5d09fb18
├─ j1 loadImage                218.4 ms  ████████████████████  97%  joined at 132.8 ms of 351.2 ms
│  ├─ memoryLookup                    –                             miss · before join · key c0d4e711
│  ├─ diskLookup                      –                             miss · before join · key 5d09fb18
│  ├─ j2 fetchOriginalImage    191.6 ms  █████████████████     85%
│  │  ├─ j3 fetchOriginalData  173.4 ms  ████████████████      77%
│  │  │  ├─ download           168.4 ms  ███████████████       75%  network · 325 KB · HTTP 200 · first byte 260.3 ms · joined at 132.6 ms of 301.0 ms · session #1
│  │  │  │  └─ networkLoad     169.0 ms  ███████████████       75%  HTTP 200 · h2 · TLS 1.3 · 151.101.1.1 · sent 178 bytes · received 325 KB
│  │  │  │     ├─ waiting      129.7 ms  ░░░░░░░░░░░░          58%
│  │  │  │     └─ response      39.3 ms              ███       17%
│  │  │  └─ diskStore            0.1 ms                 ▏           325 KB · key 5d09fb18
│  │  └─ decode                 18.0 ms                  █      8%  ImageDecoders.Default · jpeg 1440×960 · work 13.4 ms
│  ├─ decompress                26.5 ms                   ██   12%  jpeg 1440×960
│  └─ memoryStore               <0.1 ms                     ▏       key c0d4e711
├─ process                       4.6 ms                     ▕   2%  jpeg 450×300
└─ memoryStore                  <0.1 ms                     ▕       key a71c34e2
total                          225.4 ms                             finished at 16:12:58.940
```

The tree reads top to bottom as the task ran. The column is the time *this* task spent on every row, and the chart beside it says where in the task that time was, so a gap or an overlap takes no arithmetic to see; a wait is light. Only `j4` belongs to the task – `j1`, `j2`, and `j3` are the prefetcher's – which is why the lookups above the download say `before join` with no time against them, and why the download is charged the 168.4 ms this task waited for rather than the 301.0 ms it took. For the same reason the connection setup has no rows under `networkLoad`: it was over before the task existed.

The `time:` line names the part worth making faster before the tree is read. Its categories are exclusive and add up to the length of the task, so nothing is counted twice and what the stages don't account for lands in `other`. Here three quarters of the task was the download, and most of that was the server. It is also available as ``ImageTask/Metrics/timeShares``.

``ImageTask/Metrics/source`` says where the image came from, and it tells a `URLCache` hit apart from a real download – a request the session revalidated and the server answered `304` costs the time of a download and none of the bytes:

```
ImageTask #1 · success · 755.8 ms · from httpCache
transfer:    325 KB · 392 bytes on the wire · revalidated
```

Print less with ``ImageTask/Metrics/formatted(_:)``. Its ``ImageTask/Metrics/Options`` are the four sections – the header, the `time:` line, the timeline, and the `URLSession` rows – and the four columns the timeline decorates its rows with, so a report can be cut down to what its destination can use:

```swift
print(metrics.formatted(.plain)) // The sections, none of the columns
print(metrics.formatted(.all.subtracting([.chart, .percentages])))
print(metrics.formatted([.header, .breakdown]))
```

The record also reaches the pipeline delegate, with the ``ImageTask/Event/finished(_:)`` event, on the pipeline actor. That is where a logger picks it up:

```swift
final class Telemetry: ImagePipeline.Delegate {
    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished = event, let metrics = task.metrics else { return }
        send(metrics) // Encode it with JSONEncoder, or print it
    }
}
```

## Selecting a System

Make sure you select one image loading framework and stick to it. If you use more than one framework, it will prevent them from managing the system resources efficiently, such as caches. If, for any reason, you must use more than one framework, ensure that they at least share the same memory and disk caches.
