# Performance Guide

Learn how to improve image loading performance in your apps.

## Decompression

When you instantiate `UIImage` with `Data`, the data can be in a compressed format like `JPEG`. `UIImage` does _not_ eagerly decompress this data until you display it. It leads to performance issues like scroll view stuttering. To avoid it, Nuke automatically decompresses the data in the background. Decompression only runs if needed; it won't run for already processed images.

> Tip: See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.

## High-Resolution Images

Bitmapped images take a lot of space in memory. For example, take a 6000x4000px image from a professional camera. Every pixel usually requires 4 bytes (RGBA). A JPEG of such an image might use anywhere from 3 to 30 MB. But if the uncompressed bitmap takes 92 MB.

By default, Nuke stores decompressed (bitmapped) images in the memory cache. But this strategy might not be optimal for high-resolution images like this. Consider either downsampling such images or disabling memory cache for them to avoid taking too much memory.  

## Downsample Images

Ideally, the app should download the images optimized for the target device screen size; but it's not always feasible. To reduce the memory usage, downsample the images.

```swift
// Target size is in points.
let request = ImageRequest(
    url: URL(string: "http://..."),
    processors: [.resize(width: 320)]
)
```

> Tips: See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.

## Aggressive Cache

By default, Nuke uses the native HTTP cache, but it's relatively slow and is subject to the same maximum concurrent operations count as network tasks (because it's part of the URL loading system). If your app doesn't take advantage of complex HTTP cache-control parameters, consider enabling the custom aggressive disk cache. Learn more in <doc:caching>.

## Store Processed Images

By default, the aggressive disk cache (if enabled) stores original image data. If your app applies expensive processors or downsamples images, consider storing processed images instead by setting ``ImagePipeline/Configuration-swift.struct/dataCachePolicy-swift.property`` to ``ImagePipeline/DataCachePolicy/automatic`` or ``ImagePipeline/DataCachePolicy/storeEncodedImages`` depending on the use case.

## Use HEIF

To save disk space see ``ImageEncoders/ImageIO`` and ``ImageEncoders/Default/isHEIFPreferred`` option for HEIF support. By default, disabled.

## Prefetch Images

Loading data ahead of time in anticipation of its use ([prefetching](https://en.wikipedia.org/wiki/Prefetching)) is a great way to improve user experience. It's especially effective for images; it can give users an impression that there is no networking and the images are just magically always there. For more info, see <doc:prefetching>.

## Resumable Downloads

Make sure your server supports resumable downloads.

If the data task is terminated when the image is partially loaded (either because of a failure or a cancellation), the next load will resume where the previous left off. Resumable downloads require the server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators: `ETag` and `Last-Modified`. Resumable downloads are enabled by default. You can learn more in ["Resumable Downloads"](https://kean.blog/post/resumable-downloads).

## Request Priorities

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

## Create URLs Beforehand

`URL` initializer is relatively expensive because it needs to parse the input string. Make sure to create the `URL` objects in the background.

## Auto Retry

Enable [`waitsForConnectivity`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/2908812-waitsforconnectivity) on `URLSession` to indicate that the session should wait for connectivity to become available instead of failing the request immediately in case of a network failure.

## Measure

If you want to see how the system behaves, how long each operation takes, and how many are performed in parallel, enable the ``ImagePipeline/Configuration-swift.struct/isSignpostLoggingEnabled`` option and use the `os_signpost` Instrument. For more information see [Apple Documentation: Logging](https://developer.apple.com/documentation/os/logging) and [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/).
