# ``Nuke/ImagePipeline``

## Creating a Pipeline

You can start using a ``ImagePipeline/shared`` pipeline and create a custom one later if needed. To create a custom pipeline, you can use a convenience ``ImagePipeline/init(delegate:_:)`` initializer:

```swift
ImagePipeline {
    $0.dataCache = try? DataCache(name: "com.myapp.datacache")
    $0.dataCachePolicy = .automatic
}
```

You can customize ``ImagePipeline`` by initializing it with ``ImagePipeline/Configuration-swift.struct`` and ``ImagePipeline/Delegate-swift.protocol``. You can provide custom caches, data loaders, add support for new image formats, and more.

> Tip: The pipeline has two cache layers: memory cache and disk cache. By default, only the memory cache is enabled. For caching data persistently, it relies on system [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache). There are advantages to enabling a custom disk cache. You can learn more in <doc:caching>.

## Loading Images

Use ``ImagePipeline/image(for:)-(URL)`` (or the ``ImageRequest`` overload) to load an image.

```swift
let image = try await ImagePipeline.shared.image(for: url)
```

Alternatively, you can create an ``ImageTask`` and access its ``ImageTask/image`` or ``ImageTask/response`` to fetch the image. You can use ``ImageTask`` to cancel the request, change the priority of the running task, and observe its progress.

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

> Tip: The recommended way to load images with ``ImagePipeline`` is by using Async/Await API. But the pipeline also has API that works with closures and Combine publishers.

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

The pipeline avoids doing any duplicated work when loading images. Let's take two requests with the same URL but different processors as an example:

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

The pipeline will load the data only once, resize the image once and blur it only once. There is no duplicated work done. The work only gets canceled when all the registered requests are, and the priority is based on the highest priority of the registered requests.

Coalescing can be disabled using ``ImagePipeline/Configuration-swift.struct/isTaskCoalescingEnabled`` configuration option.

## Progressive Decoding

If progressive decoding is enabled, the pipeline attempts to produce previews as data arrives. The behavior is controlled by ``ImagePipeline/PreviewPolicy``, which the pipeline resolves via ``ImagePipeline/Delegate/previewPolicy(for:pipeline:)``.

**Default policy:** `.incremental` for progressive JPEGs and GIFs, `.disabled` for all other formats (baseline JPEGs, PNGs, etc.). This means only formats that benefit from incremental rendering produce previews by default.

**Available policies:**
- `.incremental` — Uses `CGImageSourceCreateIncremental` to produce a new preview as more data arrives. For JPEGs with large EXIF headers where incremental decoding fails, the decoder automatically falls back to generating a thumbnail.
- `.thumbnail` — Extracts the embedded EXIF thumbnail (if any), then stops.
- `.disabled` — No previews.

**Throttling:** The pipeline throttles progressive decoding attempts using ``ImagePipeline/Configuration-swift.struct/progressiveDecodingInterval`` (default: 0.5s). When data arrives faster than this interval, intermediate chunks are skipped. This prevents excessive decoding work on fast connections.

**Backpressure:** Every preview goes through the same processing and decompression phases as the final image. If a stage can't keep up, the pipeline waits for the current operation to finish before starting the next one. All outstanding progressive operations are canceled when the data is fully downloaded.

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

- ``image(for:)-(URL)``
- ``image(for:)-(ImageRequest)``
- ``imageTask(with:)-(URL)``
- ``imageTask(with:)-(ImageRequest)``

### Loading Images (Combine)

- ``imagePublisher(with:)-(URL)``
- ``imagePublisher(with:)-(ImageRequest)``

### Loading Images (Closures)

- ``loadImage(with:completion:)-(URL,_)``
- ``loadImage(with:completion:)-(ImageRequest,_)``
- ``loadImage(with:progress:completion:)``

### Loading Data

- ``data(for:)``
- ``loadData(with:completion:)``

### Accessing Cached Images

- ``cache-swift.property``
- ``Cache-swift.struct``

### Invalidation

- ``invalidate()``

### Error Handling

- ``Error``
