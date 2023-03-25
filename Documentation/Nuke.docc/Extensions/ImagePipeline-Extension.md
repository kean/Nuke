# ``Nuke/ImagePipeline``

## Creating a Pipeline

You can start using a ``ImagePipeline/shared`` pipeline and create a custom one later if needed. To create a custom pipeline, you can use a convenience ``ImagePipeline/init(delegate:_:)`` initializer:

```swift
ImagePipeline {
    $0.dataCache = try? DataCache(name: "com.myapp.datacache")
    $0.dataCachePolicy = .automatic
}
```

You can customize ``ImagePipeline`` by initializing it with ``ImagePipeline/Configuration-swift.struct`` and ``ImagePipelineDelegate``. You can provide custom caches, data loaders, add support for new image formats, and more.

> Tip: The pipeline has two cache layers: memory cache and disk cache. By default, only memory cache is enabled. For caching data persistently, it relies on system [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache). There are advantages of enabling a custom disk cache. You can learn more in <doc:caching>.

## Loading Images

Use ``ImagePipeline/image(for:)-4akzh`` that works with both `URL` and ``ImageRequest`` and returns an image.

```swift
let image = try await ImagePipeline.shared.image(for: url)
```

Alternatively, you can create an ``AsyncImageTask`` and access its ``AsyncImageTask/image`` or ``AsyncImageTask/response`` to fetch the image. You can use ``AsyncImageTask`` to cancel the request, change the priority of the running task, and observe its progress.

```swift
final class AsyncImageView: UIImageView {
    func loadImage() async throws {
        let imageTask = ImagePipeline.shared.imageTask(with: url)
        for await progress in imageTask.progress {
            // Update progress
        }
        imageView.image = try await imageTask.image
    }
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

``DataCache`` is a bit faster than `URLCache` and provides more control. For example, it can be configured to store processed images using ``ImagePipeline/Configuration-swift.struct/dataCachePolicy``. The downside is that without HTTP `cache-control`, the images never get validated and if the URL content changes, the app will continue showing stale data.  

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

Every image preview goes through the same processing and decompression phases as the final images. The main difference is the introduction of backpressure. If one of the stages can't process the input fast enough, the pipeline waits until the current operation is finished, and only then the next one starts. All outstanding progressive operations are canceled to save processing time when the data is fully downloaded.

## Topics

### Getting a Pipeline

- ``shared``

### Initializers

- ``init(configuration:delegate:)``
- ``init(delegate:_:)``

### Configuration

- ``configuration-swift.property``
- ``Configuration-swift.struct``

### Loading Images (Async/Await)

- ``image(for:)-4akzh``
- ``image(for:)-9egg6``
- ``imageTask(with:)-7s0fc``
- ``imageTask(with:)-6aagk``

### Loading Images (Combine)

- ``imagePublisher(with:)-8j2bd``
- ``imagePublisher(with:)-3pzm6``

### Loading Images (Closures)

- ``loadImage(with:completion:)-6q74f``
- ``loadImage(with:completion:)-43osv``
- ``loadImage(with:queue:progress:completion:)``

### Loading Data

- ``data(for:)-86rhw``
- ``data(for:)-54h5g``
- ``loadData(with:completion:)-815rt``
- ``loadData(with:completion:)-6cwk3``
- ``loadData(with:queue:progress:completion:)``

### Accessing Cached Images

- ``cache-swift.property``
- ``Cache-swift.struct``

### Invalidation

- ``invalidate()``

### Error Handling

- ``Error``
