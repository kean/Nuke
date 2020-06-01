# Image Pipeline Guide

This guide describes in detail what happens when you call `Nuke.loadImage(with: url, into: view)` and how the underlying image pipeline delivers the images to the view.

- [`Nuke.loadImage(with:into)`](#-nukeloadimage-with-into--)
- [`ImagePipeline.loadImage(with:completion:)`](#-imagepipelineloadimage-with-completion---)
- [Under the Hood](#under-the-hood)
  * [Data Loading and Caching](#data-loading-and-caching)
  * [Aggressive LRU Disk Cache](#aggressive-lru-disk-cache)
  * [Resumable Downloads](#resumable-downloads)
  * [Memory Cache](#memory-cache)
  * [Deduplication](#deduplication)
  * [Decompression](#decompression)
  * [Progressive Decoding](#progressive-decoding)
  * [Performance](#performance)
- [Benchmarks](#benchmarks)

## `Nuke.loadImage(with:into)`

This methods loads an image with the given request and displays it in the view.

Before loading a new image, the view is prepared for reuse by cancelling any outstanding requests and removing a previously displayed image.

If the image is stored in the [memory cache](#memory-cache), it is displayed immediately with no animations. If not, the image is loaded using an [image pipeline](#pipeline-fetch-image). When the image is loading, the `placeholder` is displayed. When the request completes the loaded image is displayed (or `failureImage` in case of an error) with the selected animation.

> Don't get caught in thinking that `Nuke.loadImage(with:into)` is the only way to use Nuke. This method is designed to get you up and running as quickly as possible. It is powerful and has a lot of configuration options, but if you need more control, please consider using [`ImagePipeline`](#pipeline-fetch-image) directly.

<a name="pipeline-fetch-image"/></a>
## `ImagePipeline.loadImage(with:completion:)`

This section describes the basic steps that pipeline performs when delivering an image.

> As a visual aid, use this [Block Diagram](https://github.com/kean/Nuke/blob/9.1.0/Documentation/Assets/image-pipeline.svg) (warning: the data cache portion does not yet reflect changes from Nuke 9).

1. Check if the requested image is already stored in the [memory cache](#memory-cache). If it is, deliver it to the client.
2. Check if the encoded requested image is stored in the disk cache (this feature is disabled by default). If yes, the image is
    - Decoded
    - [Decompressed](#decompression)
    - Stored in the memory cache
    - And is finally delivered to the client
3. Check if the original image data is stored in the disk cache. If it is, decode it, apply image processors, store the image in the memory cache, and deliver it to the client.

> The disk cache described in steps 2 and 3 is disabled by default. The pipeline relies on the HTTP-compliant disk cache on `URLSession` level. To learn how to enable the disk cache, see [Aggressive LRU Disk Cache](#aggressive-lru-disk-cache).

4. If all caches are empty, [load the image data](#data-loading-and-caching). If any [resumable data](#resumable-data) was left from a previous equivalent request, use it. Otherwise start fresh. When the data is loaded, perform all of the steps outlined in step 3.

> If [progressive decoding](#progerssive-decoding) is enabled, the pipeline attemps to produce a preview of any image every time a new chunk of data is loaded.

During each of these steps, the pipeline creates and performs operations, each of which is performed on its own operation queue with its own configuration. The operations respect the priority of the requests. The priority can be updated dynamically. 

## Under the Hood

### Data Loading and Caching

A `DataLoader` class uses [`URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) to load image data. The data is cached on disk using [`URLCache`](https://developer.apple.com/reference/foundation/urlcache), which by default is initialized with memory capacity of 0 MB (only stores processed images in memory) and disk capacity of 150 MB.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) to learn more about HTTP cache.

The `URLSession` class natively supports the following URL schemes: `data`, `file`, `ftp`, `http`, and `https`.

Most developers either implement their own networking layer or use a third-party framework. Nuke supports both of these workflows. You can integrate your custom networking layer by implementing `DataLoading` protocol.

> See [Third Party Libraries](https://github.com/kean/Nuke/blob/9.1.0/Documentation/Guides/third-party-libraries.md#using-other-caching-libraries) guide to learn more. See also [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin).

### Aggressive LRU Disk Cache

If HTTP caching is not your cup of tea, you can try using a custom LRU disk cache for fast and reliable *aggressive* data caching (ignores [HTTP cache control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)). You can enable it using the pipeline configuration.

```swift
ImagePipeline {
    $0.dataCache = try? DataCache(name: "com.myapp.datacache")

    // Also consider disabling the native HTTP cache, see `DataLoader`.
}
```

By default, the pipeline stores only the original image data. To store downloaded and processed images instead, set `dataCacheOptions.storedItems` to `[.finalImage]`. This option is useful if you want to store processed, e.g. downsampled images, or if you want to transcode images to a more efficient format, like HEIF.

> To save disk space see `ImageEncoders.ImageIO` and  `ImageEncoder.isHEIFPreferred` option for HEIF support.

### Resumable Downloads

If the data task is terminated (either because of a failure or a cancellation) and the image was partially loaded, the next load will resume where it was left off. Resumable downloads require the server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators (`ETag` and `Last-Modified`). Resumable downloads are enabled by default.

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

### Progressive Decoding

If progressive decoding is enabled, the pipeline attemps to produce a preview of any image every time a new chunk of data is loaded.

When the first chunk of data is downloaded, the pipeline creates an instance of a decoder which it is going to be using for the entire image loading session. When the new chunks of data are loaded, the pipleine passes these chunks to the decoder. The decoder can either produce a preview, or return `nil` if not enough data is downloaded yet.

Every image preview goes through the same processing and decompression phases that the final images do. The main difference here is the introduction of back pressure. If one of the stages of the pipeline can't process the input fast enough, the pipeline waits until the current operation is finished, and then starts the next one with the latest input. When the data is downloaded fully, all of the progressive operations are cancelled to save processing time.

### Performance

<img align="right" src="https://user-images.githubusercontent.com/1567433/59372512-f7bc0680-8d47-11e9-865e-f739f013ad49.png" width="360"/>

Nuke is tuned to do as little work on the main thread as possible. It uses multiple optimization techniques to achieve that: reducing the number of allocations, reducing dynamic dispatch, CoW, etc.

Nuke is fully asynchronous and performs well under stress. `ImagePipeline` schedules its operations on dedicated queues. Each queue limits the number of concurrent tasks, respects the request priorities, and cancels the work as soon as possible. Under extreme load, `ImagePipeline` will also rate limit requests to prevent saturation of the underlying systems.

If you want to see how the system behaves, how long each operation takes, and how many are performed in parallel, enable the `isSignpostLoggingEnabled` option and use the `os_signpost` Instrument. For more information see [Apple Documentation: Logging](https://developer.apple.com/documentation/os/logging) and [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/).

## Benchmarks

Image loading frameworks are often used in table and collection views with large number of cells. It's important that they perform well to achieve butterly smooth scrolling. 

> Please keep in mind that this performance test ([sources](https://github.com/kean/Image-Frameworks-Benchmark)) makes for a very nice looking chart, but in practice, the difference between Nuke and say SDWebImage is not going to be that dramatic. Unless you app drops frames on a table or a collection view rendering, there is no real reason to switch.

<img src="https://user-images.githubusercontent.com/1567433/61174515-92a33d00-a5a1-11e9-839f-c2a1a1237f52.png" width="800"/>
<img src="https://user-images.githubusercontent.com/1567433/61174516-92a33d00-a5a1-11e9-8915-55cf9ba519a2.png" width="800"/>
