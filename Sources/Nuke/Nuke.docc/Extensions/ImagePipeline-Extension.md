# ``Nuke/ImagePipeline``

## Creating a Pipeline

You can start by using a ``ImagePipeline/shared`` pipeline and can create a custom one later if needed. To create a custom pipeline, you can use a convenience ``ImagePipeline/init(delegate:_:)`` initializer:

```swift
ImagePipeline {
    $0.dataCache = try? DataCache(name: "com.myapp.datacache")
    $0.dataCachePolicy = .automatic
}
```

You can customize ``ImagePipeline`` by initializing it with ``ImagePipeline/Configuration-swift.struct`` and ``ImagePipelineDelegate``. You can provide custom caches, data loaders, add support for new image formats, and more.

> Tip: The pipeline has two cache layers: memory cache and disk cache. By default, only memory cache is enabled. For caching data persistently, it relies on system [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache). There are advantages of enabling a custom disk cache. You can learn more in <doc:caching>.

## Loading Images

Use ``ImagePipeline/image(for:delegate:)-2v6n0`` that works with both `URL` and ``ImageRequest`` and returns an ``ImageResponse`` with an image in case of success.

```swift
let response = try await ImagePipeline.shared.image(for: url)
let image = response.image
```

You can monitor the request by passing ``ImageTaskDelegate``. The delegate is captured as a weak reference and all callbacks are executed on the main queue by default.

```swift
final class AsyncImageView: UIImageView, ImageTaskDelegate {
    private var imageTask: ImageTask?

    func loadImage() async throws {
        imageView.image = try await pipeline.image(for: url, delegate: self).image
    }

    func imageTaskCreated(_ task: ImageTask) {
        self.imageTask = task
    }

    func imageTask(_ task: ImageTask, didReceivePreview response: ImageResponse) {
        // Gets called for images that support progressive decoding.
    }

    func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress) {
        // Gets called when the download progress is updated.
    }
}
```

You can use `ImageTask` returned by the delegate to cancel the request, change the priority of the running task, and observe its progress. But you can also the request by using Swift [`Task`](https://developer.apple.com/documentation/swift/task):

```swift
func loadImage() async throws {
    let task = Task {
        try await pipeline.image(for: url)
    }

    // Later
    task.cancel()
}
```

> Tip: The recommended way to load images ``ImagePipeline`` is by using Async/Await API. But the pipeline also has API that works with closures and Combine publishers.

## Caching

The pipeline has two cache layers: memory cache and disk cache.

``ImageCache`` stores images prepared for display in memory. It uses a fraction of available RAM and automatically removes most of the cached images when the app goes to the background or receives a memory pressure warning.

For caching data persistently, by default, Nuke uses [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache) with an increased capacity. One of its advantages is HTTP [`cache-control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) support.

You can also replace `URLCache` with a custom ``DataCache`` that ignores HTTP `cache-control` headers using ``ImagePipeline/Configuration-swift.struct/withDataCache(name:sizeLimit:)``.

```swift
ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
```

``DataCache`` is a bit faster than `URLCache` and provides more control. For example, it can be configured to store processed images using ``ImagePipeline/Configuration-swift.struct/dataCachePolicy-swift.property``. The downside is that without HTTP `cache-control`, the images never get validated and if the URL content changes, the app will continue showing stale data.  

> Tip: To learn more about caching, see <doc:caching> section.

## Coalescing

The pipeline avoids doing any duplicated work when loading images. Let's take two requests with the same URL, but different processors as an example:

```swift
let url = URL(string: "http://example.com/image")
async let first = pipeline.image(for: ImageRequest(url: url, processors: [
    .resize(size: CGSize(width: 44, height: 44)),
    .gaussianBlur(radius: 8)
]))
async let second = pipeline.image(for: ImageRequest(url: url, processors: [
    .resize(size: CGSize(width: 44, height: 44))
]))
let images = try await (first, second)
```

The pipeline will load the data only once, resize the image once and blur it also only once. There is no duplicated work done. The work only gets canceled when all the registered requests are, and the priority is based on the highest priority of the registered requests.

Coalescing can be disabled using ``ImagePipeline/Configuration-swift.struct/isTaskCoalescingEnabled`` configuration option.

## Progressive Decoding

If progressive decoding is enabled, the pipeline attempts to produce a preview of any image every time a new chunk of data is loaded. See it in action in the [demo project](https://github.com/kean/NukeDemo).

When the pipeline downloads the first chunk of data, it creates an instance of a decoder used for the entire image loading session. When the new chunks are loaded, the pipeline passes them to the decoder. The decoder can either produce a preview or return `nil` if not enough data is downloaded.

Every image preview goes through the same processing and decompression phases that the final images do. The main difference is the introduction of backpressure. If one of the stages can’t process the input fast enough, then the pipeline waits until the current operation is finished, and only then starts the next one. When the data is fully downloaded, all outstanding progressive operations are canceled to save processing time.

## Topics

### Getting a Pipeline

- ``shared``

### Initializers

- ``init(configuration:delegate:)``
- ``init(delegate:_:)``

### Configuration

- ``configuration-swift.property``
- ``Configuration-swift.struct``

### Loading Images

- ``image(for:delegate:)-9mq8k``
- ``image(for:delegate:)-2v6n0``
- ``loadImage(with:completion:)``
- ``loadImage(with:queue:progress:completion:)``
- ``imagePublisher(with:)-8j2bd``
- ``imagePublisher(with:)-3pzm6``

### Loading Data

- ``data(for:)-86rhw``
- ``data(for:)-54h5g``
- ``loadData(with:completion:)``
- ``loadData(with:queue:progress:completion:)``

### Accessing Cached Images

- ``cache-swift.property``
- ``Cache-swift.struct``

### Invalidation

- ``invalidate()``

### Error Handling

- ``Error``
