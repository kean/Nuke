# Switching to Nuke from SDWebImage

SDWebImage is an Objective-C framework first released back in 2009. In comparison, Nuke was released in 2015. Nuke has had more than enough time to build out to the same level.

[SDWebImage](https://github.com/SDWebImage/SDWebImage) is still actively maintained today and is still used by many apps. But it has a dated Objective-C API and doesn't offer great Swift support.

This document is not a comparison between the frameworks. It is designed to help you switch from SDWebImage to Nuke. This guide covers some basic scenarios common across the frameworks.

## Image View Extensions

Both frameworks have `UIKit` and `AppKit` extensions to make it easy to load images into native images views while also facilitating cell reuse.

**SDWebImage**

```swift
imageView.sd_setImage(with: URL(string: "https://example.com/image.jpeg"))
```     

**Nuke**   

```swift
Nuke.loadImage(with: "https://example.com/image.jpeg", into: imageView)
```

With Nuke, you can pass `String`, `URL`, `URLRequest`, or `ImageRequest` into the `loadImage()` method.

> Learn more in ["Image View Extensions."](https://kean.blog/nuke/guides/image-view-extensions). There is a ton of options available.

## SwiftUI

**SDWebImage**

SwiftUI is supported via a separate package, [SDWebImageSwiftUI](https://github.com/SDWebImage/SDWebImageSwiftUI).

```swift
import SwiftUI
import SDWebImageSwiftUI

struct ContentView: View {
    let url = URL(string: "https://example.com/image.jpeg")

    var body: some View {
        WebImage(url: url)
    }
}
```

**Nuke**

[NukeUI](https://github.com/kean/NukeUI) (a separate package) is a comprehensive solution for displaying lazily loaded images on Apple platforms. One of its classes is `LazyImage` and it is designed for SwiftUI.

```swift
import SwiftUI
import NukeUI

struct ContentView: View {
    let url = URL(string: "https://example.com/image.jpeg")

    var body: some View {
        LazyImage(source: url)
    }
}

```

While `LazyImage` is part of a separate package, the core framework contains a  [`FetchImage`](https://kean-org.github.io/docs/nuke/reference/10.0.0/FetchImage/) class. You can think of it as a ViewModel for your views.

```swift
struct ImageView: View {
    let url: URL

    @StateObject private var image = FetchImage()

    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray)
            image.view?
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        }
        .onAppear { image.load(url) }
        .onChange(of: url) { image.load($0) }
        .onDisappear(perform: image.reset)
    }
}
```

> Learn more about SwiftUI support in Nuke in ["SwiftUI."](https://kean.blog/nuke/guides/swiftui)

## Request Options

**SDWebImage**

```swift
imageView.sd_setImage(
    with: URL(string: "https://example.com/image.jpeg"),
    placeholderImage: nil,
    options: [
        .highPriority,
        .refreshCached
    ]
)
```

**Nuke**

```swift
let request = ImageRequest(
    url: URL(string: "https://example.com/image.jpeg"),
    priority: .high,
    options: [.reloadIgnoringCachedData]
)
Nuke.loadImage(with: request, into: imageView)
```

> Learn more in ["Image Requests."](https://kean.blog/nuke/guides/customizing-requests)

## Image Processing

Both frameworks allow you to process the loaded images using one of the built-in processors or using a custom processor.

**SDWebImage**

```swift
let transformer = SDImagePipelineTransformer(transformers: [
    SDImageResizingTransformer(size: CGSize(width: 44, height: 44), scaleMode: .aspectFill),
    SDImageRoundCornerTransformer(radius: 8, corners: .allCorners, borderWidth: 0, borderColor: nil)
])
imageView.sd_setImage(
    with: URL(string: "https://example.com/image.jpeg"),
    placeholderImage: nil,
    context: [.imageTransformer: transformer]
)
```

**Nuke**

```swift
let request = ImageRequest(
    url: URL(string: "https://example.com/image.jpeg"),
    processors: [
        ImageProcessors.Resize(size: CGSize(width: 44, height: 44)),
        ImageProcessors.RoundedCorners(radius: 8)
    ]
)
Nuke.loadImage(with: request, into: imageView)
```

If you create a custom processor, you'll notice that Nuke allows you to specify an `AnyHashable` identifier for in-memory cache. That's one of the tricks that makes Nuke [faster](https://github.com/kean/ImageFrameworksBenchmark) on the main thread than other frameworks.

> Learn more in ["Image Processing"](https://kean.blog/nuke/guides/image-processing).

## Loading Images Directly

Extensions for image view are designed to get you up and running quickly, but for advanced use cases, you have direct access to the underlying subsystems responsible for image loading.

**SDWebImage**

```swift
let task = SDWebImageManager.shared.loadImage(
    with: URL(string: "https://example.com/image.jpeg"),
    options: [],
    progress: nil
) { image, error, _, _, _, _  in
    if let image = image {
        print("Fetched image: \(image)")
    } else {
        print("Failed with \(error)")
    }
}
task?.cancel()
```

**Nuke**

```swift
let url = URL(string: "https://example.com/image.jpeg")
let task = ImagePipeline.shared.loadImage(with: url) { result in
    switch result {
    case .success(let result):
        print("Fetched image: \(result.image)")
    case .failure(let error):
        print("Failed with \(error)")
    }
}
task.cancel()
task.priority = .high // Change priority dynamically (Nuke-only)
```

Nuke also has great Combine support (see ["Combine"](https://kean.blog/nuke/guides/combine)) and allows you to attach to the underlying data requests as well. Nuke also has impressive task coalescing support that prevents the pipeline from doing any duplicated work. You can learn more about coalescing and the pipeline in general in ["Image Pipeline Guide."](https://kean.blog/nuke/guides/image-pipeline-guide)

> Learn more in ["Image Pipeline."](https://kean.blog/nuke/guides/image-pipeline)

## Caching

**SDWebImage**

Designed to work with a custom cache. There are options to fallback to a URLCache.

**Nuke**

By default, is initialized with a native HTTP disk cache. Can be configured to work with a custom aggressive LRU disk cache.
    

```swift
ImagePipeline(configuration: .withURLCache) // Default cache
ImagePipeline(configuration: .withDataCache) // Aggressive cache
```

> Learn more in ["Caching."](https://kean.blog/nuke/guides/caching)

## Other Features

This guide only covered the most basic APIs. To learn more about Nuke, please refer to the official website with the [comprehensive documentation](https://kean.blog/nuke/guides/welcome) on every Nuke feature.

