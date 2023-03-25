# Getting Started

Learn about main Nuke features and APIs.

## Image Pipeline

``ImagePipeline`` downloads images, caches, and prepares them for display. To load an image, use an async method ``ImagePipeline/image(for:)-4akzh`` returning an image.

```swift
let image = try await ImagePipeline.shared.image(for: url)
```

To get more control over the download, use ``ImagePipeline/imageTask(with:)-7s0fc`` to create an ``AsyncImageTask`` and then access its ``AsyncImageTask/image`` or ``AsyncImageTask/response`` to receive the image.

```swift
func loadImage() async throws {
    let imageTask = ImagePipeline.shared.imageTask(with: url)
    for await progress in imageTask.progress {
        // Update progress
    }
    imageView.image = try await imageTask.image
}
```

> Tip: You can start by using a ``ImagePipeline/shared`` pipeline and create a custom one later if needed. To create a custom pipeline, use a convenience ``ImagePipeline/init(delegate:_:)`` initializer or one of the pre-defined configurations, such as ``ImagePipeline/Configuration-swift.struct/withDataCache``.

> The documentation uses Async/Await APIs in the examples, but ``ImagePipeline`` also has equivalent completion-based and Combine APIs.

## Image Request

``ImageRequest`` allows you to set image processors, downsample images, change the request priority, and provide other options. See ``ImageRequest`` reference to learn more.

```swift
let request = ImageRequest(
    url: URL(string: "http://example.com/image.jpeg"),
    processors: [.resize(width: 320)],
    priority: .high,
    options: [.reloadIgnoringCachedData]
)
let image = try await pipeline.image(for: request)
```

> Tip: You can use built-in processors or create custom ones. Learn more in <doc:image-processing>.

## Caching

Nuke has two cache layers: memory cache and disk cache.

``ImageCache`` stores images prepared for display in memory. It uses a fraction of available RAM and automatically removes most cached images when the app goes to the background or receives a memory pressure warning.

For caching data persistently, by default, Nuke uses [`URLCache`](https://developer.apple.com/documentation/foundation/urlcache) with an increased capacity. One of its advantages is HTTP [`cache-control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) support.

You can also replace `URLCache` with a custom ``DataCache`` that ignores HTTP `cache-control` headers using ``ImagePipeline/Configuration-swift.struct/withDataCache(name:sizeLimit:)``.

```swift
ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
```

``DataCache`` is faster than `URLCache` and provides more control. For example, it can be configured to store processed images using ``ImagePipeline/Configuration-swift.struct/dataCachePolicy``. The downside is that without HTTP `cache-control`, the images never get validated, and if the URL content changes, the app will continue showing stale data.  

> Tip: To learn more about caching, see <doc:caching> section.

## Performance

One of the key Nuke features is performance. It does a lot by default: custom cache layers, coalescing of equivalent requests, resumable HTTP downloads, and more. But there are certain things that the user of the framework can also do to use it more effectively, for example, <doc:prefetching>. To learn more about what you can do to improve image loading performance in your apps, see <doc:performance-guide>.

To optimize performance, you need to be able to monitor it. And that's where [Pulse](https://github.com/kean/Pulse) network logging framework comes in handy. It is optimized for working with images and is easy to integrate:

```swift
(ImagePipeline.shared.configuration.dataLoader as? DataLoader)?.delegate = URLSessionProxyDelegate()
```

## NukeUI

**NukeUI** is a module that provides async image views for SwiftUI, UIKit, and AppKit.

```swift
struct ContainerView: View {
    var body: some View {
        LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    }
}
```

Learn more in NukeUI [documentation](https://kean-docs.github.io/nukeui/documentation/nukeui/).
