# Configuration

Nuke virtually unlimited possibilities for customization and most of them are done using ``ImagePipeline/Configuration-swift.struct``.

## Default Configuration

The default image pipeline is initialized with the following dependencies:

```swift
// Shared image cache with a size limit of ~20% of available RAM.
imageCache = ImageCache.shared

// Data loader with a default `URLSessionConfiguration` and a custom `URLCache`
// with memory capacity 0, and disk capacity 150 MB.
dataLoader = DataLoader()

// Custom aggressive disk cache is disabled by default.
dataCache = nil

// By default uses the decoder from the global registry and the default encoder.
makeImageDecoder = ImageDecoderRegistry.shared.decoder(for:)
makeImageEncoder = { _ in ImageEncoders.Default() }
```

> Tip: You have two built-in configurations to pick from ``ImagePipeline/Configuration-swift.struct/withURLCache`` (default), and ``ImagePipeline/Configuration-swift.struct/withDataCache`` that have different caching behavior. Learn more in ["Caching"](<doc:caching>).

Each operation in the pipeline runs on a dedicated queue:

```swift
dataLoadingQueue.maxConcurrentOperationCount = 6
dataCachingQueue.maxConcurrentOperationCount = 2
imageDecodingQueue.maxConcurrentOperationCount = 1
imageEncodingQueue.maxConcurrentOperationCount = 1
imageProcessingQueue.maxConcurrentOperationCount = 2
imageDecompressingQueue.maxConcurrentOperationCount = 2
```

There is a list of pipeline settings which you can tweak:

```swift
// A queue for completion and progress callbacks.
callbackQueue = DispatchQueue.main

// Automatically decompress images in the background by default.
isDecompressionEnabled = true

// Configure what content to store in the custom disk cache.
dataCachePolicy = .storeOriginalData

// Avoid doing any duplicated work when loading or processing images.
isTaskCoalescingEnabled = true

// Progressive decoding is an opt-in feature because it is resource intensive.
isProgressiveDecodingEnabled = true

// Don't store progressive previews in memory cache.
isStoringPreviewsInMemoryCache = true

// If the data task is terminated (either because of a failure or a
// cancellation) and the image was partially loaded, the next load will
// resume where it was left off.
isResumableDataEnabled = true

// Rate limit the requests to prevent trashing of the subsystems.
isRateLimiterEnabled = true
```

And also a few global options shared between all pipelines:

```swift
// Enable to start using `os_signpost` to monitor the pipeline
// performance using Instruments.
ImagePipeline.Configuration.isSignpostLoggingEnabled = false
```

## Custom Pipeline

If you want to build a system that fits your specific needs, you won't be disappointed. There are a _lot of things_ to tweak. You can set custom data loaders and caches, configure image encoders and decoders, change the number of concurrent operations for each stage, disable and enable features like deduplication and rate-limiting, and more.

> Tip: To learn more, see the inline documentation for ``ImagePipeline/Configuration-swift.struct`` and [Image Pipeline Guide](<doc:image-pipeline-guide>).

The protocols that can be used for customization:

- ``DataLoading`` – Download (or return cached) image data
- ``DataCaching`` – Store image data on disk
- ``ImageDecoding`` – Convert data into images
- ``ImageEncoding`` - Convert images into data
- ``ImageProcessing`` – Apply image transformations
- ``ImageCaching`` – Store images into a memory cache

To create a pipeline with a custom configuration, either call the ``ImagePipeline/init(configuration:delegate:)`` initializer or use the convenience one:

```swift
let pipeline = ImagePipeline {
    $0.dataLoader = ...
    $0.dataLoadingQueue = ...
    $0.dmageCache = ...
    ...
}
```

And then set the new pipeline as the default one:

```swift
ImagePipeline.shared = pipeline
```

## ImagePipeline Delegate

New in [Nuke 10](https://github.com/kean/Nuke/releases/tag/10.0.0) is ``ImagePipelineDelegate``. It has a variety of advanced per-request customization options covered by the API reference.

To give you an example, it allows you to observe the pipeline events:

```swift
final class ImagePipelineObserver: ImagePipelineDelegate {
    var startedTaskCount = 0
    var cancelledTaskCount = 0
    var completedTaskCount = 0

    var events = [ImageTaskEvent]()

    func pipeline(_ pipeline: ImagePipeline,
                  imageTask: ImageTask,
                  didReceiveEvent event: ImageTaskEvent) {
        switch event {
        case .started:
            startedTaskCount += 1
        case .cancelled:
            cancelledTaskCount += 1
        case .completed(let result):
            completedTaskCount += 1
        default:
            break
        }
        events.append(event)
    }
}
```

You can pass the delegate when instantiating the pipeline. The delegate is strongly retained.

```swift
let observer = ImagePipelineObserver()
ImagePipeline(delegate: observer)
```
