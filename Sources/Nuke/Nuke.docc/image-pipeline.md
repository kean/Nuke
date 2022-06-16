# Image Pipeline

At the core of Nuke is the ``ImagePipeline`` class that you can use to load images directly. While built-in UI extensions have a rich set of APIs, they still can't cover all scenarios. And this is where the pipeline comes in.

## ImagePipeline

You can start by using a shared pipeline and can configure a custom one later if needed (see <doc:configuration>).

```swift
ImagePipeline.shared.loadImage(with: url) { result in
   print("task completed")
)
```

### Load Image

Use Use ``ImagePipeline/loadImage(with:queue:progress:completion:)`` method to load an image for the given request.

```swift
let task = ImagePipeline.shared.loadImage(
    with: url,
    progress: { preview, completed, total in
        print("progress updated")
    },
    completion: { result in
        print("task completed")
    }
)
```

If you look at the method signature, you'll see that it accepts ``ImageRequestConvertible`` as a request. Every time you see it, it means that the method works with the following types: ``ImageRequest``, [`URL`](https://developer.apple.com/documentation/foundation/url), [`String`](https://developer.apple.com/documentation/swift/string), and [`URLRequest`](https://developer.apple.com/documentation/foundation/urlrequest).

When you call this method, the pipeline checks if the image exists in any of the cache layers, prioritizing the fastest caches (memory cache). If there is no cached data, the pipeline starts the download. When the data is loaded, it decodes the data, applies the processors, and decompresses the image in the background.

> Tip: See <doc:image-pipeline-guide> to learn how images are downloaded and processed.

The completion closure always gets called asynchronously. By default, it gets called on the main thread, but you can customize it using an optional `queue` parameter or setting a global callback queue (``ImagePipeline/Configuration-swift.struct/callbackQueue``) for the pipeline. To check if the image is stored in a memory cache synchronously, use a subcript.

### Load Data

Use ``ImagePipeline/loadData(with:queue:progress:completion:)`` method to load image data.

```swift
ImagePipeline.shared.loadData(with: url) { result in
   print("task completed")
)
```

### Image Publisher

``ImagePipeline`` also has Combine support with ``ImagePipeline/imagePublisher(with:)`` method.

```swift
public extension ImagePipeline {
    func imagePublisher(with request: ImageRequestConvertible) -> ImagePublisher
}
```

> Tip: Learn more about Combine support in <doc:combine>.

## ImageTask

When you start the request, the pipeline returns an ``ImageTask`` object, which can be used for cancellation and more.

```swift
let task = ImagePipeline.shared.loadData(with: url) { result in
   print("task completed")
)
```

The pipeline maintains a strong reference to the task until the request finishes or fails; you do not need to maintain a reference to the task unless it is useful to do so for your app’s internal bookkeeping purposes.

### Cancellation

Mark task for cancellation.

```swift
task.cancel()
```

### Priority

Change the priority of the outstanding task.

```swift
task.priority = .high
```

### Progress

In addition to the `progress` closure, you can observe the progress of the download using `Foundation.Progress`.

```swift
let progress = task.progress
```

## Builder Extension

Nuke is easy to learn because it uses only the basic Swift language features and is written in an idiomatic way. [NukeBuilder](https://github.com/kean/NukeBuilder) package provides a different way to use it.

### Load Image

Downloading an image and applying processors.

```swift
ImagePipeline.shared.image(with: URL(string: "https://"))
    .resize(width: 320)
    .blur(radius: 10)
    .priority(.high)
    .options([.reloadIgnoringCachedData])
    .load { result in
        print(result)
    }
    
// Returns a discardable `ImageTask`.
```

Starting with Nuke 10, instead of loading an image right away, you can also create a Combine publisher.

```swift
import NukeBuilder

ImagePipeline.image(with: "https://example.com/image.jpeg")
    .resize(width: 320)
    ...
    .publisher
```

### Display in Image View

You can take the same image that you described previously and automatically display it in an image view.

```swift
let image = ImagePipeline.shared.image(with: URL(string: "https://"))
    .resize(width: 320)
    .blur(radius: 10)
    .priority(.high)
    
let imageView: UIImageView

image.display(in: imageView)
    .transition(.fadeIn(duration: 0.33))
    .placeholder(UIImage.placeholder)
    .contentMode(.center, for: .placeholder)
    .load()
```

When you use `display(in:)` method, the returned object has options specific to the image view display: `transition`, `placeholder`, etc. These options match available options provided by ``ImageLoadingOptions``.
