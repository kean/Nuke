# Getting Started

Learn about main Nuke features and APIs.

## Image Pipeline

``ImagePipeline`` implements all steps needed to download an image and prepare it for display. You can start by using a shared pipeline and can configure a custom one later if needed. To load an image, use an async method ``ImagePipeline/image(for:delegate:)`` that returns ``ImageResponse`` containing an image.

```swift
let response = try await ImagePipeline.shared.image(for: url)
let image = response.image
```

When you call this method, the pipeline checks if the image exists in any of its cache layers. If there is no cache, the pipeline starts the download. When the data is loaded, it decodes the data, applies the processors, and prepares the image for display by decompressing it.

> `ImagePipeline` also has completion-based and Combine APIs, but the documentation uses Async/Await in most of the examples.

You can monitor the request by passing ``ImageTaskDelegate``.

```swift
func loadImage() async throws {
    let _ = try await pipeline.image(for: url, delegate: self)
}

func imageTaskCreated(_ task: ImageTask) {
    // Gets called immediately when the task is created.
}

func imageTask(_ task: ImageTask, didReceivePreview response: ImageResponse) {
    // When downloading and image that supports progerssive decoding, previews are delivered here.
}

func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress) {
    // Gets called when the download progress is updated.
}
```

The delegate is captured weakly and the callbacks are executed on the main queue by default.

> Tip: You can customize ``ImagePipeline`` by initializing it with ``ImagePipeline/Configuration-swift.struct`` and ``ImagePipelineDelegate``. You can also provide custom caches, data loaders, adding support for new image formats, and more. Learn more in <doc:image-pipeline-configuration>.

## Image Request

``ImageRequest`` allows you to apply other image processors, downsample images, change the request priority, and provide other options.

```swift
let request = ImageRequest(
    url: URL(string: "http://example.com/image.jpeg"),
    processors: [.resize(size: imageView.bounds.size)],
    priority: .high,
    options: [.reloadIgnoringCacheData]
)
let response = try await pipeline.image(for: url)
```

> Most APIs accept types that conform to ``ImageRequestConvertible``. By default, it includes `URL`, `URLRequest`, and ``ImageRequest`` itself. Learn more in <doc:image-requests>.

## Caching

Nuke has two cache layers: memory cache and disk cache. By default, only memory cache is enabled. For caching data persistently, Nuke relies on system [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache).

``ImageCache`` stores images prepared for display (decompressed or "bitmapped") in memory. By default, it uses a fraction of available RAM and automatically removes most of the cached images when the app goes to the background or receives a memory pressure warning. It uses an LRU cleanup policy (the least recently used are removed first).

By default, the pipeline creates a [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache) instance with an increased capacity to by used on the `URLSession` level. One of the advantages of using `URLCache` is that it supports HTTP caching. It can also be a disadvantage in case the cache control is misconfigured on the server.

To enable a custom disk cache (``DataCache``), use ``ImagePipeline/Configuration-swift.struct/withDataCache(sizeLimit:)``.

```swift
ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
```

The custom disk cache ignores HTTP cache control headers and stores all downloaded images. ``DataCache`` is a bit faster than `URLCache` and provides more control to the client. For example, it can be configured to store only processed images. The downside is that the images don't get validated and if the URL content changes, the app will continue showing stale data.  

> Tip: To learn more about caching, see <doc:caching> section.

## Performance

One of the key Nuke's features is performance. It does a lot by default: custom cache layers, coalescing of equivalent requests, resumable HTTP downloads, and more. But there are certain things that the user of the framework can also do to use it more effectively, for example, <doc:prefetching>. To learn more about what you can do to improve image loading performance in your apps, see <doc:performance-guide>.
