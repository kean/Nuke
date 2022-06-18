# Performance Guide

Learn how to improve image loading performance in your apps.

## Coalescing

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

Nuke will load the data only once, resize the image once and blur it also only once. There is no duplicated work done. The work only gets canceled when all the registered requests are, and the priority is based on the highest priority of the registered requests.

Coalescing can be disabled using ``ImagePipeline/Configuration-swift.struct/isTaskCoalescingEnabled`` configuration option.

## Decompression

When you instantiate `UIImage` with `Data`, the data can be in a compressed format like `JPEG`. `UIImage` does _not_ eagerly decompress this data until you display it. It leads to performance issues like scroll view stuttering. To avoid it, Nuke automatically decompresses the data in the background. Decompression only runs if needed; it won't run for already processed images.

> Tip: See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.

## Progressive Decoding

If progressive decoding is enabled, the pipeline attempts to produce a preview of any image every time a new chunk of data is loaded. See it in action in the [demo project](https://github.com/kean/NukeDemo).

When the pipeline downloads the first chunk of data, it creates an instance of a decoder used for the entire image loading session. When the new chunks are loaded, the pipeline passes them to the decoder. The decoder can either produce a preview or return nil if not enough data is downloaded.

Every image preview goes through the same processing and decompression phases that the final images do. The main difference is the introduction of backpressure. If one of the stages can’t process the input fast enough, then the pipeline waits until the current operation is finished, and only then starts the next one. When the data is fully downloaded, all outstanding progressive operations are canceled to save processing time.

## Caching

### Enable Aggressive Cache

By default, Nuke uses the native HTTP cache, but it's relatively slow and is subject to the same maximum concurrent operations count as network tasks (because it's part of the URL loading system). If your app doesn't take advantage of complex HTTP cache-control parameters, consider enabling the custom aggressive disk cache.

> The default behavior will most likely change in Nuke 10.

### Store Processed Images

By default, the aggressive disk cache (if enabled) stores original image data. If your app applies expensive processors or downsamples images, consider storing processed images instead by setting ``ImagePipeline/Configuration-swift.struct/dataCachePolicy-swift.property`` to ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/automatic`` or ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeEncodedImages`` depending on the use case.

### Use HEIF

To save disk space see ``ImageEncoders/ImageIO`` and ``ImageEncoders/Default/isHEIFPreferred`` option for HEIF support. By default, disabled.

## Downsample Images

Ideally, the app should download the images optimized for the target device screen size; but it's not always feasible. To reduce the memory usage, downsample the images.

```swift
// Target size is in points.
let request = ImageRequest(
    url: URL(string: "http://..."),
    processors: [ImageProcessors.Resize(size: imageView.bounds.size)]
)
```

> Tips: See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.

## Prefetch Images

Loading data ahead of time in anticipation of its use ([prefetching](https://en.wikipedia.org/wiki/Prefetching)) is a great way to improve user experience. It's especially effective for images; it can give users an impression that there is no networking and the images are just magically always there.

To implement prefetching, see <doc:prefetching>

## Resumable Downloads

Make sure your server supports resumable downloads. By default, the pipeline enables resumable downloads on the client side.

## Request Priorities

Nuke allows you to set the request priority and update it for outstanding tasks. It uses priorities for prefetching: the requests created by the prefetcher all have `.low` priority to make sure they don't interfere with the "regular" requests. See <doc:prefetching> to learn more.

There are many other creative ways to use priorities. For example, when the user taps an image in a grid to open it full screen, you can lower the priority of the requests for the images that are not visible on the screen.

```swift
final class ImageView: UIView {
    private let task: ImageTask?

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)

        task?.priority = newWindow == nil ? .low : .high
    }
}
```

## Create URLs Beforehand

`URL` initializer is relatively expensive because it needs to parse the input string. It might take more time than the call to ``Nuke/loadImage(with:options:into:completion:)`` itself. Make sure to create the `URL` objects in the background.

## Auto Retry

Enable [`waitsForConnectivity`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/2908812-waitsforconnectivity) on `URLSession` to indicate that the session should wait for connectivity to become available instead of failing the request immediately in case of a network failure.

## Measure

If you want to see how the system behaves, how long each operation takes, and how many are performed in parallel, enable the ``ImagePipeline/Configuration-swift.struct/isSignpostLoggingEnabled`` option and use the `os_signpost` Instrument. For more information see [Apple Documentation: Logging](https://developer.apple.com/documentation/os/logging) and [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/).
