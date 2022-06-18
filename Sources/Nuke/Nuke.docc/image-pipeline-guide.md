
### Data Loading and Caching


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

## Performance

Nuke is tuned to have at little overhead as possible. It uses multiple optimization techniques to achieve that: reducing the number of allocations, reducing dynamic dispatch, CoW, etc. There is virtually nothing left in Nuke that could be changed to improve main thread performance.

If you measure just Nuke code, it takes about **0.004 ms** (4 *micro*seconds) on the main thread per request and about **0.03 ms** (30 microseconds) overall, as measured on iPhone 11 Pro using Nuke 10.0.

Nuke is fully asynchronous and performs well under stress. `ImagePipeline` schedules its operations on dedicated queues. A queue limits the number of concurrent tasks, manages the request priorities, cancels the work when needed. Under extreme load, `ImagePipeline` will also rate-limit requests to prevent saturation of the underlying systems.

> Tip: To learn more about Nuke performance, see ["Nuke 9"](https://kean.blog/post/nuke-9).

If you want to see how the system behaves, how long each operation takes, and how many are performed in parallel, enable the `isSignpostLoggingEnabled` option and use the `os_signpost` Instrument. For more information see [Apple Documentation: Logging](https://developer.apple.com/documentation/os/logging) and [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/).

## Benchmarks

Image loading frameworks are often used in table and collection views with a large number of cells. They must perform well to achieve buttery smooth scrolling.

> Please keep in mind that this performance test ([sources](https://github.com/kean/Image-Frameworks-Benchmark)) makes for a very nice-looking chart, but in practice, the difference between Nuke and say SDWebImage will be that dramatic. Unless your app drops frames on a table or a collection view rendering, there is no real reason to switch.

![](bench-01)
![](bench-02)

## Tasks

Nuke has an incredible number of performance [features](https://kean.blog/post/nuke-9): progressive decoding, prioritization, coalescing of tasks, cooperative cancellation, parallel processing, backpressure, prefetching. It forces Nuke to be massively concurrent. The actor model is just part of the solution. To manage individual image requests, it needed a structured approach for managing async tasks.

The solution is [`Task`](https://github.com/kean/Nuke/blob/93c187ab98ab02f8c891d1fa40ffe92a1591f524/Sources/Tasks/Task.swift#L18), which is a part of the internal infrastructure. When you request an image, Nuke creates a dependency tree with multiple tasks. When a similar image request arrives (e.g. the same URL, but different processors), an existing subtree can serve as a dependency of another task.

Nuke supports progressive decoding and task design reflects that. Tasks send events *upstream*: data chunks, image scans, progress updates, errors. Tasks send priority updates and cancellation requests *downstream*. This design is inspired by reactive programming, but is optimized for Nuke. Tasks are much simpler and faster than a typical generalized reactive programming implementation. The complete implementation takes just 237 lines.

Some tasks implement *backpressure*. For example, if you are fetching a progressive JPEG and have an expensive processor, such as blur, the processing task will only produce processed images as fast as it can, skipping the scans it has no capacity to handle.

All of the tasks are synchronozied on a single serial dispatch queue. This a simple and reliable way to achieve performance and thread safety.

> To learn more about how Nuke manages concurrency, see [Concurrency in Nuke](https://kean.blog/post/concurrency).


## Plugins

// TODO: This should be incorporated in individual customization options 

The image pipeline is easy to customize and extend. Check out the following first-class extensions and packages built by the community.


## [NukeUI](https://github.com/kean/NukeUI)

 [NukeUI](https://github.com/kean/NukeUI) – A comprehensive solution for displaying lazily loaded images on Apple platforms.

## [Nuke Builder](https://github.com/kean/NukeBuilder)

 [Nuke Builder](https://github.com/kean/NukeBuilder) – A set of convenience APIs inspired by SwiftUI to create image requests.

## [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin)

 [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) – Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire) and combine the power of both frameworks.

## [RxNuke](https://github.com/kean/RxNuke)

[RxNuke](https://github.com/kean/RxNuke) – [RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with many examples.

## [WebP Plugin](https://github.com/ryokosuge/Nuke-WebP-Plugin)

 [WebP Plugin](https://github.com/ryokosuge/Nuke-WebP-Plugin) – [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge).

## [Gifu Plugin](https://github.com/kean/Nuke-Gifu-Plugin)

[Gifu Plugin](https://github.com/kean/Nuke-Gifu-Plugin) – Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs.

## [FLAnimatedImage Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin)

[FLAnimatedImage Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin) – Use [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) to load and display [animated GIFs]((https://www.youtube.com/watch?v=fEJqQMJrET4)).

## [Xamarin NuGet](https://github.com/roubachof/Xamarin.Forms.Nuke)

[Xamarin NuGet](https://github.com/roubachof/Xamarin.Forms.Nuke) – Makes it possible to use Nuke from Xamarin.
