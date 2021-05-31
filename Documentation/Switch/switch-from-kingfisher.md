# Switching to Nuke from Kingfisher

Both frameworks appeared at roughly the same time in 2015. So they've been around almost as long as Swift has been.

Kingfisher was [heavily inspired](https://github.com/onevcat/Kingfisher/tree/1.0.0) by [SDWebImage](https://github.com/SDWebImage/SDWebImage). In fact, many APIs directly match the APIs found in SDWebImage. The most recent versions became better Swift citizens, but you can still find some Objective-C/SDWebImage influences, e.g. `progressBlock` naming.

Nuke, on the other hand, was designed from the ground up according to the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

This document is not a comparison between the frameworks. It is designed to help you switch from Kingfisher to Nuke. This guide covers some basic scenarios common across the frameworks.

## Image View Extensions

Both frameworks have `UIKit` and `AppKit` extensions to make it easy to load images into native images views while also facilitating cell reuse.

**Kingfisher**

```swift
imageView.kf.setImage(with: URL(string: "https://example.com/image.jpeg"))
```     

**Nuke**   

```swift
Nuke.loadImage(with: "https://example.com/image.jpeg", into: imageView)
```

With Nuke, you can pass `String`, `URL`, `URLRequest`, or `ImageRequest` into the `loadImage()` method.

> Learn more in ["Image View Extensions."](https://kean.blog/nuke/guides/image-view-extensions). There is a ton of options available.

## SwiftUI

**Kingfisher**

```swift
import SwiftUI
import Kingfisher

struct ContentView: View {
    let url = URL(string: "https://example.com/image.jpeg")

    var body: some View {
        KFImage(url)
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

**Kingfisher**

```swift
imageView.kf.setImage(
    with: URL(string: "https://example.com/image.jpeg"),
    options: [
        .downloadPriority(10),
        .forceRefresh
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

The request API in Nuke not only offers a wide range of options but is also designed for performance. The request takes only 46 bytes in memory (compare with 520 bytes of `KingfisherParsedOptionsInfo`), and, unlike Kingfisher, doesn't require any pre-processing. This is one of the many reasons Nuke is [faster](https://github.com/kean/ImageFrameworksBenchmark).

> Learn more in ["Image Requests."](https://kean.blog/nuke/guides/customizing-requests)

## Image Processing

Both frameworks allow you to process the loaded images using one of the built-in processors or using a custom processor.

**Kingfisher**

```swift
let processor = DownsamplingImageProcessor(size: CGSize(width: 44, height: 44))
    |> RoundCornerImageProcessor(cornerRadius: 8)
imageView.kf.setImage(
    with: URL(string: "https://example.com/image.jpeg"),
    options: [.processor(processor)]
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

**Kingfisher**

```swift
guard let url = URL(string: "https://example.com/image.jpeg") else {
    return // KingfisherManager requires a non-optional URL
}
let task = KingfisherManager.shared.retrieveImage(with: url) { result in
    switch result {
    case .success(let result):
        print("Fetched image: \(result.image)")
    case .failure(let error):
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

**Kingfisher**

Designed to work with a custom cache with no clear way to disable it.

**Nuke**

By default, is initialized with a native HTTP disk cache. Can be configured to work with a custom aggressive LRU disk cache.
    

```swift
ImagePipeline(configuration: .withURLCache) // Default cache
ImagePipeline(configuration: .withDataCache) // Aggressive cache
```

> Learn more in ["Caching."](https://kean.blog/nuke/guides/caching)

## Other Features

This guide only covered the most basic APIs. To learn more about Nuke, please refer to the official website with the [comprehensive documentation](https://kean.blog/nuke/guides/welcome) on every Nuke feature.
