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

Use ``ImagePipeline/image(for:delegate:)`` that returns an ``ImageResponse`` containing an image in case of success.

```swift
let response = try await ImagePipeline.shared.image(for: url)
let image = response.image
```

You can monitor the request by passing ``ImageTaskDelegate``. The delegate is captured as a weak reference and all callbacks are executed on the main queue by default.

```swift
private let imageTask: ImageTask?

func loadImage() async throws {
    imageView.image = try await pipeline.image(for: url, delegate: self).image
}

func imageTaskCreated(_ task: ImageTask) {
    self.imageTask = task
}

func imageTask(_ task: ImageTask, didReceivePreview response: ImageResponse) {
    // When downloading and image that supports progerssive decoding, previews are delivered here.
}

func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress) {
    // Gets called when the download progress is updated.
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

- ``image(for:delegate:)``
- ``loadImage(with:completion:)``
- ``loadImage(with:queue:progress:completion:)``
- ``imagePublisher(with:)``

### Loading Data

- ``data(for:)``
- ``loadData(with:completion:)``
- ``loadData(with:queue:progress:completion:)``

### Accessing Cached Images

- ``cache-swift.property``
- ``Cache-swift.struct``

### Invalidation

- ``invalidate()``

### Error Handling

- ``Error``
