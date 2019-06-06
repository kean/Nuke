<br/>

<p align="left"><img src="https://cloud.githubusercontent.com/assets/1567433/13918338/f8670eea-ef7f-11e5-814d-f15bdfd6b2c0.png" height="180"/>

# Powerful Image Loading System

<p align="left">
<img src="https://img.shields.io/cocoapods/v/Nuke.svg?label=version">
<img src="https://img.shields.io/badge/platforms-iOS%2C%20macOS%2C%20watchOS%2C%20tvOS-lightgrey.svg">
<img src="https://img.shields.io/badge/test%20coverage-100%25-brightgreen.svg">
<a href="https://travis-ci.org/kean/Nuke"><img src="https://img.shields.io/travis/kean/Nuke/master.svg"></a>
</p>

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/blob/master/Documentation/Migrations).

Nuke provides a simple and efficient way to download and display images in your app. Behind its straightforward and concise API is an architecture with virtually unlimited possibilities for customization, which enables its unique set of features.

> **Fast LRU memory and disk cache** · **Smart background decompression** · **Rich image processing** · **Resumable downloads** · **Intelligent deduplication** · **Request prioritization** · **Rate limiting** · **Progressive JPEG, WebP** · **Animated images** · **Prefetching** · **Alamofire, WebP, Gifu, FLAnimatedImage integrations** · **Reactive extensions**

<br/>

## Getting Started

Nuke is easy to learn and use. Here is an overview of its APIs and features:

- **Image View Extensions** ‣ [Load Image into Image View](#load-image-into-image-view) | [Placeholders, Transitions, and More](#placeholders-transitions-and-more) | [`ImageRequest`](#imagerequest)
- **Image Processing** ‣ [`Resize`](#resize) | [`GaussianBlur`, Core Image](#gaussianblur-core-image) | [Custom Processors](#custom-processors) | [Smart Decompression](#smart-decompression)
- **Image Pipeline** ‣ [Load Image](#load-image) | [`ImageTask`](#imagetask) | [Default Image Pipeline](#default-image-pipeline) | [Customize Image Pipeline](#customize-image-pipeline)
- **Caching** ‣ [LRU Memory Cache](#lru-memory-cache) | [HTTP Disk Cache](#http-disk-cache) | [Aggressive LRU Disk Cache](#aggressive-lru-disk-cache)
- **Advanced Features** ‣ [Preheat Images](#image-preheating) | [Progressive Decoding](#progressive-decoding) | [Animated Images](#animated-images) | [WebP](#webp) | [RxNuke](#rxnuke)

To learn more see a full [**API Reference**](https://kean.github.io/Nuke/reference/7.3/index.html), and check out the demo project included in the repository. When you are ready to install, follow the [**Installation Guide**](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Installation%20Guide.md). See [**Requirements**](#h_requirements) for a list of supported platforms.

To learn about the image pipeline itself, see the dedicated section:

- **Image Pipeline** ‣ [Overview](#h_design) | [Data Loading and Caching](#data-loading-and-caching) | [Resumable Downloads](#resumable-downloads) | [Memory Cache](#memory-cache) | [Deduplication](#deduplication) | [Performance](#performance) | [Extensions](#h_plugins)

If you'd like to contribute to Nuke see [**Contributing**](#h_contribute).
 
<br/>

## Image View Extensions

### Load Image into Image View

You can load an image and display it in an image view with a single line of code:

```swift
Nuke.loadImage(with: url, into: imageView)
```

Nuke will check if the image exists in the memory cache, and if it does, will instantly display it. If not, the image data will be loaded, decoded, processed and decompressed in the background.

> See [Image Pipeline Overview](#h_design) to learn more.

### In a List

When requesting a new image for the existing view, the previous outstanding request gets canceled automatically and the view is prepared for reuse, making it extremely easy to load images in lists.

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    ...
    Nuke.loadImage(with: url, into: cell.imageView)
    ...
}
```

> The requests also get canceled automatically when the views get deallocated. To cancel the request manually, call `Nuke.cancelRequest(for: imageView)`.

### Placeholders, Transitions and More

Use `ImageLoadingOptions` to customize the way images are loaded and displayed. You can provide a `placeholder`, select one of the built-in `transitions` or provide a custom one.

```swift
Nuke.loadImage(
    with: url,
    options: ImageLoadingOptions(
        placeholder: UIImage(named: "placeholder"),
        transition: .fadeIn(duration: 0.33)
    ),
    into: imageView
)
```

You can even customize _content modes_ for each image type:

```swift
let options = ImageLoadingOptions(
    placeholder: UIImage(named: "placeholder"),
    failureImage: UIImage(named: "failureImage"),
    contentModes: .init(
        success: .scaleAspectFill,
        failure: .center,
        placeholder: .center
    )
)
```

> In case you want all image views to have the same behavior, you can modify `ImageLoadingOptions.shared`.

### `ImageRequest`

`ImageRequest` struct describes the requests and allows you to set image processors (more on them in the next section), change the priority and more:

```swift
let request = ImageRequest(
    url: URL(string: "http://..."),
    processors: [ ImageProcessor.Resize(size: imageView.bounds.size ],
    priority: .high
)
```

There are also a few advanced options available via `ImageRequestOptions` struct. For example, you can provide a `filteredURL` to be used as a key for caching in case the URL itself contains some transient query parameters.

```swift
let request = ImageRequest(
    url: URL(string: "http://example.com/image.jpeg?token=123")!,
    options: ImageRequestOptions(
        filteredURL: "http://example.com/image.jpeg"
    )
)
```

> There are more options available, to see all of them check the inline documentation for `ImageRequestOptions`.

<br/>

## Image Processing

Nuke features a powerful and efficient image processing infrastructure with quite a few built-in image processors and the ability to add more.

### `Resize`

To resize the image, use `ImageProcessor.Resize`:

```swift
ImageRequest(url: url, processors: [ImageProcessor.Resize(size: imageView.bounds.size)])
```

By default, the target size is in points. When the image is loaded, Nuke will scale it to fill the target area maintaining the image aspect ratio. To also crop the image set `crop` to `true`.

> There are a few other options available, see `ImageProcessor.Resize` documentation for more info.

There are more built-in processors like `ImageProcessor.CornerRadius`, `ImageProcessor.Circle`, and more yet to come.

### `GaussianBlur`, Core Image

To apply gaussian blur, use `ImageProcessor.GaussianBlur`.

Gaussian blur is powered by the native `CoreImage` framework. To apply other filters, use `ImageProcessor.CoreImageFilter`:

```swift
ImageProcessor.CoreImageFilter(name: "CISepiaTone")
```

> For a complete list of Core Image filters see [Core Image Filter Reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html).

### Custom Processors

Each built-in processor implements a public `ImageProcessing` protocol, which you can also implement to provide your own custom processors:

```swift
public protocol ImageProcessing {
    var identifier: String { get }
    var hashableIdentifier: AnyHashable { get }

    func process(image: Image, context: ImageProcessingContext?) -> Image?
}
```

The `process` method is quite straightforward, but the identifiers need some explanation. The first one, `var identifier: String` is used for caching processed images. The second one, is used by memory caches for which string manipulation are too slow.

There are two other options to implement custom processors: `ImageProcessor.Anonymous` which is initialized with a closure for one-off processors, and `ImageProcessor.Composition` for combining multiple processors into one.

### Smart Decompression

When you instantiate `UIImage` with `Data`, the data can be in compressed format like `JPEG`. `UIImage` does _not_ eagerly decompress this data until you display it. This leads to performance issues like scroll view stuttering. To avoid these issues, Nuke automatically decompresses the image data on the background thread. Decompression only runs if needed, for example, Nuke won't do any redundant work if you have already forced image decompression by applying one of the image processors.

> See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.

<br/>

## Image Pipeline

### Load Image

At the core of Nuke is `ImagePipeline` class. Use the pipeline directly to load images without displaying them:

```swift
let task = ImagePipeline.shared.loadImage(
    with: url,
    progress: { _, completed, total in
        print("progress updated")
    },
    completion: { result: Result<ImageResponse, ImagePipeline.Error> in
        print("task completed")
    }
)
```

### `ImageTask`

When you start the request, the pipeline returns an `ImageTask` object, which you can use to later cancel the request or dynamically change its priority:

```swift
task.cancel()
task.priority = .high
```

> In some cases, you only want to download the data without doing any expensive decoding or processing. You can do that with `loadData(with:progress:completion:)` API.

### Default Image Pipeline

The default image pipeline configuration is this:

```swift
ImagePipeline {
    // Shared image cache with a size limit equal to ~20% of available RAM.
    $0.imageCache = ImageCache.shared

    // Data loader with a default `URLSessionConfiguration` and a custom
    // shared `URLCache` instance:
    //
    // public static let sharedUrlCache = URLCache(
    //     memoryCapacity: 0,
    //     diskCapacity: 150 * 1024 * 1024, // 150 MB
    //     diskPath: "com.github.kean.Nuke.Cache"
    //  )
    $0.dataLoader = DataLoader()

    // Custom agressive disk cache is disabled by default.
    $0.dataCache = nil

    // By default uses the decoder from the global registry and the default encoder.
    $0.makeImageDecoder = { context in ImageDecoderRegistry.shared.decoder(for: context) }
    $0.makeImageEncoder = { _ in ImageEncoder() }

    // Each operation is executed on a dedicated queue:
    $0.dataLoadingQueue.maxConcurrentOperationCount = 6
    $0.dataCachingQueue.maxConcurrentOperationCount = 2
    $0.imageDecodingQueue.maxConcurrentOperationCount = 1
    $0.imageEncodingQueue.maxConcurrentOperationCount = 1
    $0.imageProcessingQueue.maxConcurrentOperationCount = 2
    $0.imageDecompressingQueue.maxConcurrentOperationCount = 2

    // Automatically decompress images in the background by default.
    $0.isDecompressionEnabled = true

    // Configure which images to store in the custom disk cache.
    #0.isDataCachingForOriginalImageDataEnabled = true
    $0.isDataCachingForProcessedImagesEnabled = false

    // Avoid doing any duplicated work when loading or processing images.
    $0.isDeduplicationEnabled = true

    // Rate limit the requests to prevent trashing of the subsytems.
    $0.isRateLimiterEnabled = true

    // Progressive decoding is an opt-in feature because it is resource intensive.
    $0.isProgressiveDecodingEnabled = false

    // If the data task is terminated (either because of a failure or a
    // cancellation) and the image was partially loaded, the next load will
    // resume where it was left off.
    $0.isResumableDataEnabled = true
}
```

There are also some global settings:

```swift
ImagePipeline.Configuration.isAnimatedImageDataEnabled = false

// Enable to start using `os_signpost` to monitor the pipeline
// performance using Instruments.
ImagePipeline.Configuration.isSignpostLoggingEnabled = false
```

### Customize Image Pipeline

If you want to build a system that fits your specific needs, you won't be disappointed.

The pipeline configuration is described by `ImagePipeline.Configuration` struct. And there are a lot of things to tweak. You can set custom data loaders and caches, configure image encoders and decoders, change the number of concurrent operations for each individual pipeline stage, disable and enable features like deduplication and rate limiting.

- `DataLoading` – Download (or return cached) image data
- `DataCaching` – Store image data on disk
- `ImageDecoding` – Convert data into images
- `ImageEncoding` - Convert images into data
- `ImageProcessing` – Apply image transformations
- `ImageCaching` – Store images into memory cache

To learn more about these options see the inline documentation for `ImagePipeline.Configuration` and also [Image Pipeline Overview](#h_design) section.

When you know what settings to change, it's easy to do with the convenience `ImagePipeline` initializer:

```swift
let pipeline = ImagePipeline {
    $0.dataLoader = ...
    $0.dataLoadingQueue = ...
    $0.imageCache = ...
    ...
}
```

When you created your dream pipeline, you can set it as a shared one:

```swift
ImagePipeline.shared = pipeline
```

<br/>

## Caching

### LRU Memory Cache

Default Nuke's `ImagePipeline` has two cache layers.

First, there is a memory cache for storing processed images which are ready for display. You can get a direct access to this cache via `ImageCache.shared`:

```swift
// Configure cache
ImageCache.shared.costLimit = 1024 * 1024 * 100 // 100 MB
ImageCache.shared.countLimit = 100
ImageCache.shared.ttl = 120 // Invalidate image after 120 sec

// Read and write images
let request = ImageRequest(url: url)
ImageCache.shared[request] = image
let image = ImageCache.shared[request]

// Clear cache
ImageCache.shared.removeAll()
```

> `ImageCache` uses LRU algorithm – least recently used entries are removed first during the sweep.

### HTTP Disk Cache

To store unprocessed image data Nuke uses a `URLCache` instance:

```swift
// Configure cache
DataLoader.sharedUrlCache.diskCapacity = 100
DataLoader.sharedUrlCache.memoryCapacity = 0

// Read and write responses
let request = ImageRequest(url: url)
let _ = DataLoader.sharedUrlCache.cachedResponse(for: request.urlRequest)
DataLoader.sharedUrlCache.removeCachedResponse(for: request.urlRequest)

// Clear cache
DataLoader.sharedUrlCache.removeAllCachedResponses()
```

### Aggressive LRU Disk Cache

If `URLCache` is not your cup of tea, you can try using a custom LRU disk cache for fast and reliable *aggressive* data caching (ignores [HTTP cache control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)). You can enable it using the pipeline configuration.

```swift
ImagePipeline {
    $0.dataCache = try! DataCache(name: "com.myapp.datacache")
}
```

If you enable aggressive disk cache, make sure that you also disable native URL cache (see `DataLoader`), or you might end up storing the same image data twice.

By default, the pipeline will only store original image data in the data cache. But it can also store processed image data for you. To enable this feature set `isDataCachingForProcessedImagesEnabled` configuration option to `true`.

<br/>

## Advanced Features

### Image Preheating

Prefetching images in advance can dramatically improve your app's user experience. Nuke provides an `ImagePreheater` to do just that:

```swift
let preheater = ImagePreheater()
preheater.startPreheating(with: urls)

// Cancels all of the preheating tasks created for the given requests.
preheater.stopPreheating(with: urls)
```

Keep in mind that prefetching takes up users' data and puts extra pressure on CPU and memory. To reduce the CPU and memory usage you have an option to choose only the disk cache as a prefetching destination:

```swift
// The preheater with `.diskCache` destination will skip image data decoding
// entirely to reduce CPU and memory usage. It will still load the image data
// and store it in disk caches to be used later.
let preheater = ImagePreheater(destination: .diskCache)
```

On iOS, you can use [prefetching APIs](https://developer.apple.com/reference/uikit/uitableviewdatasourceprefetching) in combination with `ImagePreheater` to automatically prefer images in lists.

### Progressive Decoding

To enable progressive image decoding set `isProgressiveDecodingEnabled` configuration option to `true`.

```swift
let pipeline = ImagePipeline {
    $0.isProgressiveDecodingEnabled = true
}
```

And that's it, the pipeline will automatically do the right thing and deliver the progressive scans via `progress` closure as they arrive:

```swift
let imageView = UIImageView()
let task = ImagePipeline.shared.loadImage(
    with: url,
    progress: { response, _, _ in
        if let response = response {
            imageView.image = response?.image
        }
    },
    completion: { result in
        imageView.image = try? result.get().image
    }
)
```

> See "Progressive Decoding" demo to view progressive JPEG in practice.

### Animated Images

Nuke extends `UIImage` with `animatedImageData` property. To enable it, set `ImagePipeline.Configuration.isAnimatedImageDataEnabled` to `true`. If you do, then the pipeline will start attaching the original image data to the animated images.

There is no built-in way to render those images, but there are two extensions available: [FLAnimatedImage](https://github.com/kean/Nuke-FLAnimatedImage-Plugin) and [Gifu](https://github.com/kean/Nuke-Gifu-Plugin) which are both fast and efficient.

> `GIF` is not the most efficient format for transferring and displaying animated images. The current best practice is to [use short videos instead of GIFs](https://developers.google.com/web/fundamentals/performance/optimizing-content-efficiency/replace-animated-gifs-with-video/) (e.g. `MP4`, `WebM`). There is a PoC available in the demo project which uses Nuke to load, cache and display an `MP4` video.

### WebP

WebP support is provided by [Nuke WebP Plugin](https://github.com/ryokosuge/Nuke-WebP-Plugin) built by [Ryo Kosuge](https://github.com/ryokosuge). Please follow the instructions from the repo.

### RxNuke

[RxNuke](https://github.com/kean/RxNuke) adds [RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke and enables some common use cases:

- [Going from low to high resolution](https://github.com/kean/RxNuke#going-from-low-to-high-resolution)
- [Loading the first available image](https://github.com/kean/RxNuke#loading-the-first-available-image)
- [Showing stale image while validating it](https://github.com/kean/RxNuke#showing-stale-image-while-validating-it)
- [Load multiple images, display all at once](https://github.com/kean/RxNuke#load-multiple-images-display-all-at-once)
- [Auto retry on failures](https://github.com/kean/RxNuke#auto-retry)
- And [more...](https://github.com/kean/RxNuke#use-cases)

To get a taste of what you can do with this extension, take a look at how easy it is to load the low resolution image first and then switch to high resolution:

```swift
let pipeline = ImagePipeline.shared
Observable.concat(pipeline.loadImage(with: lowResUrl).orEmpty,
                  pipeline.loadImage(with: highResUtl).orEmpty)
    .subscribe(onNext: { imageView.image = $0 })
    .disposed(by: disposeBag)
```

<br/>

<a name="h_design"></a>
# Image Pipeline Overview

Here's what happens when you perform a call like `Nuke.loadImage(with: url, into: view)`.

> As a visual aid, use this [Block Diagram](https://github.com/kean/Nuke/blob/master/Documentation/Assets/image-pipeline.svg).

First, Nuke synchronously checks if the image is stored in the memory cache. If it's not, Nuke calls `pipeline.loadImage(with: request)` method.

The pipeline first checks if the image or image data exists in any its caches. It checks if the processsed image exists in memory cache, then if the processed image data exists in the custom data cache (disabled by default), then if the data cache contains the original image data. Only if the are no cached data, the pipleine will start loading the data.

When the data is loaded the pipeline decodes the data (creates `UIImage` object from `Data`), applies the processors specified in the request, and decompresses the image in the background.

### Data Loading and Caching

A built-in `DataLoader` class implements `DataLoading` protocol and uses [`URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) to load image data. The data is cached on disk using a [`URLCache`](https://developer.apple.com/reference/foundation/urlcache) instance, which by default is initialized with a memory capacity of 0 MB (Nuke stores images in memory, not image data) and a disk capacity of 150 MB.

The `URLSession` class natively supports the `data`, `file`, `ftp`, `http`, and `https` URL schemes. Image pipeline can be used with any of these schemes as well.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) fore more on this topic

> See [Third Party Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries) guide to learn how to use a custom data loader or cache

Most developers either implement their own networking layer or use a third-party framework. Nuke supports both of these workflows. You can integrate your custom networking layer by implementing `DataLoading` protocol.

> See [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that implements `DataLoading` protocol using [Alamofire](https://github.com/Alamofire/Alamofire) framework

### Resumable Downloads

If the data task is terminated (either because of a failure or a cancelation) and the image was partially loaded, the next load will resume where it was left off. 

Resumable downloads require server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators (`ETag` and `Last-Modified`). The resumable downloads are enabled by default.

> By default, resumable data is stored in a small and efficient memory cache.

### Memory Cache

The processed images are stored in a fast in-memory cache (`ImageCache`). It uses [LRU (least recently used)](https://en.wikipedia.org/wiki/Cache_algorithms#Examples) replacement algorithm and has a limit which prevents it from using more than ~20% of available RAM. `ImageCache` automatically evicts images on memory warnings and removes portion of its contents when the application enters background.

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

Nuke will load the image data only once, resize the image once and apply the blur also only once. There is no duplicated work done at any stage. The work only gets cancelled when all the registered requests are and the priority is based on the highest priority of the registerd requests.

> Deduplication can be disabled using `isDeduplicationEnabled` configuration option.

### Performance

Performance is one of the key differentiating factors of Nuke. The framework is tuned to do as little work on the main thread as possible. It uses multiple optimization techniques to achieve that: reducing number of allocations, reducing dynamic dispatch, backing some structs by reference typed storage to reduce ARC overhead, etc.

Nuke is fully asynchronous and performs well under stress. `ImagePipeline` schedules its operations on dedicated queues. Each queue limits the number of concurrent tasks, respects the request priorities, and cancels the work as soon as possible. Under the extreme load, `ImagePipeline` will also rate limit the requests to prevent trashing of the underlying systems.

Nuke has `os_signpost` integration for measuring performance. If you want to see visually how the system behaves, how long each operation takes and how many are performed in parallel, enable signposts using `isSignpostLoggingEnabled` option and use `os_signpost` Instrument. For more information see [Apple Documentation: Logging](https://developer.apple.com/documentation/os/logging) and [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/).

<a name="h_plugins"></a>
### Extensions

There is a variety of extensions available for Nuke, some of which are built by the community.

|Name|Description|
|--|--|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples of common use cases solved by Rx|
|[**Alamofire**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire) and combine the power of both frameworks|
|[**WebP**](https://github.com/ryokosuge/Nuke-WebP-Plugin)| **[Community]** [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge)|
|[**Gifu**](https://github.com/kean/Nuke-Gifu-Plugin)|Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs|
|[**FLAnimatedImage**](https://github.com/kean/Nuke-AnimatedImage-Plugin)|Use [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) to load and display [animated GIFs]((https://www.youtube.com/watch?v=fEJqQMJrET4))|

<br/>

<a name="h_contribute"></a>
# Contribution

[Nuke's roadmap](https://trello.com/b/Us4rHryT/nuke) is managed in Trello and is publically available. If you'd like to contribute, please feel free to create a PR.

<a name="h_requirements"></a>
# Requirements

| Nuke              | Swift             | Xcode              | Platforms                                         |
|-------------------|-------------------|--------------------|---------------------------------------------------|
| Nuke 8            | Swift 5.0         | Xcode 10.2         | iOS 10.0 / watchOS 3.0 / macOS 10.12 / tvOS 10.0  |
| Nuke 7.6 – 7.6.3  | Swift 4.2 – 5.0   | Xcode 10.1 – 10.2  | iOS 10.0 / watchOS 3.0 / macOS 10.12 / tvOS 10.0  |
| Nuke 7.2 – 7.5.2  | Swift 4.0 – 4.2   | Xcode 9.2 – 10.1   | iOS 9.0 / watchOS 2.0 / macOS 10.10 / tvOS 9.0    | 

# License

Nuke is available under the MIT license. See the LICENSE file for more info.
