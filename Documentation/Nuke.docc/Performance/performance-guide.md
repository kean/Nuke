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

## Data Loading Slots

Prefetching and the images on screen share ``ImagePipeline/Configuration-swift.struct/dataLoadingQueue``, which runs up to 6 downloads at a time. A download that has started can't be interrupted, so the requests with a priority lower than `.normal` run in at most 3 of the slots, and an image on screen starts loading right away even when prefetching is busy.

The limit, ``TaskQueue/reservedTaskCount``, only matters when there is more low-priority work than it allows: an ``ImagePrefetcher`` with `maxConcurrentRequestCount` above 3 (the default is 2), several prefetchers at once, or requests that you start or lower to `.low` or `.veryLow`. When an image appears on screen while it's still being prefetched, its download gets the higher priority and frees its slot.

Reserving more slots gets the images on screen sooner, but slows prefetching down when it has more work than slots. Reserve 4 for large images, such as a feed or a gallery, and 0–2 if prefetching has to keep up with fast scrolling through thumbnails.

```swift
ImagePipeline.shared = ImagePipeline {
    $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 6, reservedTaskCount: 4)
}
```

> Tip: To see whether the images on screen wait for a slot, enable ``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled`` and check the ``ImageTask/Metrics/Category/queue`` share of their ``ImageTask/Metrics/timeShares``.

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

The print is the record in full: a header, one line that says where the time went, and the tree of the work the task waited on – with the requests `URLSession` made nested under the download that made them. Here is a feed image, resized for the cell, on a host the app hadn't talked to yet:

```
ImageTask #2 "feed" · success · 140.9 ms · from network
url:         https://cdn.example.com/photos/1024.jpg
processors:  com.github.kean/nuke/resize?s=(900.0, 900.0),cm=.aspectFill,crop=false,upscale=false
priority:    normal
image:       1350×900 · jpeg · 4.9 MB in memory
transfer:    317 KB
pipeline:    44A3F653
time:        network 93.6 ms (66%) · process 42.5 ms (30%) · cache 0.5 ms · decode 0.3 ms · queue 0.1 ms · other 3.8 ms (3%)

pending                              <0.1 ms  ▏                          started at 17:24:14.677
j4 loadImage [resize]               139.5 ms  ████████████████████  99%
├─ memoryLookup                      <0.1 ms  ▏                          miss · key aa429747
├─ diskLookup                         0.3 ms  ▏                          miss · key f6d8540b
├─ j5 loadImage                      96.3 ms  ██████████████        68%
│  ├─ memoryLookup                   <0.1 ms  ▏                          miss · key 38c326ae
│  ├─ diskLookup                      0.1 ms  ▏                          miss · key 19d1c77c
│  └─ j6 fetchOriginalImage          96.0 ms  ██████████████        68%
│     ├─ j7 fetchOriginalData        95.2 ms  ██████████████        68%
│     │  ├─ download                 93.6 ms  ██████████████        66%  network · 317 KB · HTTP 200 · first byte 50.3 ms · session #2
│     │  │  └─ networkLoad           93.1 ms  ██████████████        66%  HTTP 200 · h2 · TLS 1.3 · 151.101.1.1 · sent 164 bytes · received 318 KB
│     │  │     ├─ blocked             1.4 ms  ░                      1%
│     │  │     ├─ domainLookup        1.0 ms   ▏                     1%
│     │  │     ├─ connect            10.0 ms   █                     7%
│     │  │     ├─ secureConnection   21.0 ms    ███                 15%
│     │  │     ├─ request            <0.1 ms       ▏
│     │  │     ├─ waiting            16.1 ms       ░░               11%
│     │  │     └─ response           43.3 ms         ███████        31%
│     │  └─ diskStore                <0.1 ms                ▏            317 KB · key 19d1c77c
│     └─ decode                       0.3 ms                ▏            ImageDecoders.Default · jpeg 1440×960
├─ process                           42.6 ms                ██████  30%  jpeg 1350×900
└─ memoryStore                        0.1 ms                     ▕       key aa429747
total                               140.9 ms                             finished at 17:24:14.818
```

The tree reads top to bottom as the task ran. The column is the time *this* task spent on every row, and the chart beside it says where in the task that time was, so a gap or an overlap takes no arithmetic to see; a wait is light. Nothing here overlaps: the pipeline looked in both caches, downloaded 317 KB, decoded it, and resized it, in that order. A third of the download went on reaching the host: the domain lookup, the connection, and the handshake all sit in front of the first byte, and a connection the app already had open would have skipped the 31 ms of `connect` and `secureConnection`.

The `time:` line names the part worth making faster before the tree is read. Its categories are exclusive and add up to the length of the task, so nothing is counted twice and what the stages don't account for lands in `other`. Here two thirds of the task was the network and most of the rest was the resize. It is also available as ``ImageTask/Metrics/timeShares``.

When a task attaches to work another task started, the record says so, and it charges the task only for the part it waited on. The same image, asked for by a cell 48 ms after a prefetcher had started fetching it:

```
coalesced:   yes · shared with #2 (j4, j5, j6)
time:        network 44.4 ms (65%) · process 10.9 ms (16%) · decompress 9.3 ms (14%) · cache 0.3 ms · decode 0.3 ms · queue 0.2 ms · other 3.0 ms (4%)

pending                        <0.1 ms  ▏                          started at 17:25:08.898
j7 loadImage [resize]          67.1 ms  ████████████████████  98%
├─ memoryLookup                <0.1 ms  ▏                          miss · key aa429747
├─ diskLookup                   0.1 ms  ▏                          miss · key f6d8540b
├─ j4 loadImage                55.6 ms  █████████████████     81%  joined at 47.7 ms of 103.3 ms
│  ├─ memoryLookup                   –                             miss · before join · key 38c326ae
│  ├─ diskLookup                     –                             miss · before join · key 19d1c77c
│  ├─ j5 fetchOriginalImage    46.2 ms  ██████████████        68%
│  │  ├─ j6 fetchOriginalData  45.5 ms  ██████████████        67%
│  │  │  ├─ download           44.4 ms  █████████████         65%  network · 317 KB · HTTP 200 · first byte 86.4 ms · joined at 46.7 ms of 91.1 ms · session #2
…
```

Only `j7` is this task's. `j4`, `j5`, and `j6` are the prefetcher's: the lookups it had already done by the time this task joined print `–` and say `before join`, and the download is charged the 44.4 ms this task waited for rather than the 91.1 ms it ran for. Every attributed duration is clamped to the lifetime of the task, so the records of two tasks that shared a download never add up to more than the download.

``ImageTask/Metrics/source`` says where the image came from, and it tells a `URLCache` hit apart from a real download – a request the session revalidated and the server answered `304` costs the time of a download and none of the bytes:

```
ImageTask #2 "feed" · success · 31.0 ms · from httpCache
transfer:  317 KB · 81 bytes on the wire · revalidated
```

Print less with ``ImageTask/Metrics/formatted(_:)``. Its ``ImageTask/Metrics/Options`` are the four sections – the header, the `time:` line, the timeline, and the `URLSession` rows – and the four columns the timeline decorates its rows with, so a report can be cut down to what its destination can use:

```swift
print(metrics.formatted(.plain)) // The sections, none of the columns
print(metrics.formatted(.all.subtracting([.chart, .percentages])))
print(metrics.formatted([.header, .breakdown]))
```

The record also reaches the pipeline delegate, with the ``ImageTask/Event/finished(_:)`` event, on the pipeline actor. That is where a logger picks it up:

```swift
final class Telemetry: ImagePipeline.Delegate, Sendable {
    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished = event, let metrics = task.metrics else { return }
        send(metrics) // Encode it with JSONEncoder, or print it
    }
}
```

## Selecting a System

Make sure you select one image loading framework and stick to it. If you use more than one framework, it will prevent them from managing the system resources efficiently, such as caches. If, for any reason, you must use more than one framework, ensure that they at least share the same memory and disk caches.
