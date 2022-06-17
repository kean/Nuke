# Image Pipeline

Learn how to use ``ImagePipeline`` to load images.

## Overview

Use ``ImagePipeline`` to load images using Async/Await, closures, or Combine publishers. The recommended way is to use Async/Await as the other two will be deprecated in future versions.

## Creating a Pipeline

You can start by using a shared pipeline (``ImagePipeline/shared``) and can create a custom one later if needed. To create a custom pipeline, you can use a convenience ``ImagePipeline/init(delegate:_:)`` initializer:

```swift
ImagePipeline {
    $0.dataCache = try? DataCache(name: "com.myapp.datacache")
    $0.dataCachePolicy = .automatic
}
```

> Tip: There are many ways to customize the pipeline. For example, you can set ``ImagePipelineDelegate`` to provide custom option on a per-request basis. To learn more, see <doc:image-pipeline-configuration>.

## Loading Images

In this section, you'll learn how to load images using ``ImagePipeline``.

### Load an Image (Async/Await)

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

func imageTask(_ task: ImageTask, didProduceProgressiveResponse response: ImageResponse) {
    // When downloading and image that supports progerssive decoding, previews are delivered here.
}

func imageTask(_ task: ImageTask, didUpdateProgress progress: (completed: Int64, total: Int64)) {
    // Gets called when the download progress is updated.
}
```

> Tip: You can customize ``ImagePipeline`` by initializing it with ``ImagePipeline/Configuration-swift.struct`` and ``ImagePipelineDelegate``. You can also provide custom caches, data loaders, adding support for new image formats, and more. Learn more in <doc:image-pipeline-configuration>.

You can use `ImageTask` returned by the delegate to cancel the request, change the priority of the running task, and observe its progress. But you can also the request by using Swift `Task`:

```swift
func loadImage() async throws {
    let task = Task {
        try await pipeline.image(for: url)
    }

    // Later
    task.cancel()
}
```

### Load an Image (Closures)

``ImagePipeline`` also has a closure-based APIs that supports the same features as an Async/Await-based one. To load an image using closures, use ``ImagePipeline/loadImage(with:queue:progress:completion:)``.

```swift
let task = ImagePipeline.shared.loadImage(
    with: url,
    progress: { preview, completed, total in
        // Show a preview or update the download progress indicator
    },
    completion: { result in
        // Handle result of type Result<ImageResponse, ImagePipeline.Error>
    }
)
```

The completion closure always gets called asynchronously. By default, it gets called on the main thread, but you can customize it using an optional `queue` parameter or setting a global callback queue (``ImagePipeline/Configuration-swift.struct/callbackQueue``) for the pipeline. To check if the image is stored in a memory cache synchronously, use a subcript.

When you start the request, the pipeline returns an ``ImageTask`` object, which can be used for cancellation and more. The pipeline maintains a strong reference to the task until the request finishes or fails. You can use ``ImageTask`` to control the outstanding request.

```swift
let task = ...

// Cancel an outstanding request.
task.cancel()

// Update the priority of the outstanding request.
task.setPriority(.high)

// Monitor the download progress using `Foundation.Progress` (not recommended).
let progress = task.progress
```

### Load an Image (Combine)

``ImagePipeline`` also has Combine support with ``ImagePipeline/imagePublisher(with:)`` method.

```swift
public extension ImagePipeline {
    func imagePublisher(with request: any ImageRequestConvertible) -> AnyPublisher<ImageResponse, Error>
}
```

## Loading Data

There is also a way to download underlying image data using ``ImagePipeline/data(for:)``.

``swift
let (data, urlResponse) = try await pipeline.data(for: url)
```

It also has a closure-based API:

```swift
ImagePipeline.shared.loadData(with: url) { result in
   print("task completed")
)
```

## Accessing Cached Image and Data

You can access any caching layer directly, but the pipeline also offers a convenience ``ImagePipeline/Cache-swift.struct`` API.

```swift
// It works with ImageRequestConvertible so it supports String, URL,
// URLRequest, and ImageRequest
let image = pipeline.cache[URL(string: "https://example.com/image.jpeg")!]
pipeline.cache[ImageRequest(url: url)] = nil
pipeline.cache["https://example.com/image.jpeg"] = ImageContainer(image: image)
```

> Tip: There are more ``ImagePipeline/Cache-swift.struct`` APIs and they are all covered in <doc:image-pipeline-cache>. 

