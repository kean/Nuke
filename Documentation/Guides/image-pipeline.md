# Image Pipeline Guide

This guide describes in detail what happens when you perform a call like `Nuke.loadImage(with: url, into: view)` and how the underlying image pipeline work and what feature it has.

### `Nuke.loadImage(with:into)`

First, Nuke synchronously checks if the image is stored in the memory cache. If the image is not in memory, Nuke calls `pipeline.loadImage(with: request)`.

> As a visual aid, use this [Block Diagram](https://github.com/kean/Nuke/blob/8.0/Documentation/Assets/image-pipeline.svg).

As an overview, theses are the basic steps that the pipeline performs to provide the requested image

1. Check if the requested image is already stored in the [memory cache](#memory-cache) and returns it if it does.
2. Check if the encoded requested image is stored in the disk cache (this feature is disable by default). If yes, decodes it, [decompresses](#decompression) it, stores in the memory cache, and serves to the client.
3. Check if the original image data is stored in the disk cache, decodes it, applies image processors, stores the image in the memory cache, and serves it.

> The disk cache described in steps 2 and 3 is disabled by default. To learn how to enable it, see [Aggressive LRU Disk Cache](https://github.com/kean/Nuke/tree/image-pipeline#aggressive-lru-disk-cache).

4. If no caches are found, the pipeline starts loading the image data. Before it does, it checks whether any [resumable data](#resumable-data) was left from the previous equivalent request. When the data is loaded, the pipeline performs all of the steps outlined in step 3.

During each of these steps, the pipeline creates and performs operations each of which is performed on its own operation queue with its own configuration. The operations respect the priority of the requests. The priority can be updated dynamically.

### Data Loading and Caching

A `DataLoader` class uses [`URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) to load image data. The data is cached on disk using [`URLCache`](https://developer.apple.com/reference/foundation/urlcache), which by default is initialized with memory capacity of 0 MB (only stores processed images in memory) and disk capacity of 150 MB.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) to learn more about HTTP cache.

The `URLSession` class natively supports the following URL schemes: `data`, `file`, `ftp`, `http`, and `https`.

Most developers either implement their own networking layer or use a third-party framework. Nuke supports both of these workflows. You can integrate your custom networking layer by implementing `DataLoading` protocol.

> See [Third Party Libraries](https://github.com/kean/Nuke/blob/8.0/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries) guide to learn more. See also [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin).

### Resumable Downloads

If the data task is terminated (either because of a failure or a cancelation) and the image was partially loaded, the next load will resume where it was left off. Resumable downloads require the server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators (`ETag` and `Last-Modified`). The resumable downloads are enabled by default.

### Memory Cache

The processed images are stored in a fast in-memory cache (`ImageCache`). It uses [LRU (least recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm and has a limit of ~20% of available RAM. `ImageCache` automatically evicts images on memory warnings and removes a portion of its contents when the application enters background mode.

### Deduplication

The pipeline avoids doing any duplicated work when loading images. For example, let's take these two requests:

```swift
let url = URL(string: "http://example.com/image")
pipeline.loadImage(with: ImageRequest(url: url, processors: [
    ImageProcessor.Resize(size: CGSize(width: 44, height: 44)),
    ImageProcessor.GaussianBlur(radius: 8)
]))
pipeline.loadImage(with: ImageRequest(url: url, processors: [
    ImageProcessor.Resize(size: CGSize(width: 44, height: 44))
]))
```

Nuke will load the data only once, resize the image once and blur it also only once. There is no duplicated work done. The work only gets cancelled when all the registered requests are, and the priority is based on the highest priority of the registered requests.

> Deduplication can be disabled using `isDeduplicationEnabled` configuration option.

### Decompression

When you instantiate `UIImage` with `Data`, the data can be in a compressed format like `JPEG`. `UIImage` does _not_ eagerly decompress this data until you display it. This leads to performance issues like scroll view stuttering. To avoid these it, Nuke automatically decompresses the data in the background. Decompression only runs if needed, it won't run for already processed images.

> See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.

### Performance

<img align="right" src="https://user-images.githubusercontent.com/1567433/59372512-f7bc0680-8d47-11e9-865e-f739f013ad49.png" width="360"/>

Nuke is tuned to do as little work on the main thread as possible. It uses multiple optimization techniques to achieve that: reducing the number of allocations, reducing dynamic dispatch, CoW, etc.

Nuke is fully asynchronous and performs well under stress. `ImagePipeline` schedules its operations on dedicated queues. Each queue limits the number of concurrent tasks, respects the request priorities, and cancels the work as soon as possible. Under the extreme load, `ImagePipeline` will also rate limit the requests to prevent saturation of the underlying systems.

If you want to see how the system behaves, how long each operation takes, and how many are performed in parallel, enable the `isSignpostLoggingEnabled` option and use the `os_signpost` Instrument. For more information see [Apple Documentation: Logging](https://developer.apple.com/documentation/os/logging) and [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/).
