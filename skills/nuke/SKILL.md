---
name: nuke
description: Load, cache, process, and display remote images in Swift apps with Nuke and NukeUI (LazyImage, ImageLoader, LazyImageView, AnimatedImage, ImagePipeline, ImagePrefetcher). Use when writing or debugging code that imports Nuke or NukeUI, when an image doesn't show up, or when an app on iOS, macOS, tvOS, watchOS, or visionOS needs image loading, thumbnails, GIFs, prefetching, or an image cache. Covers Nuke 14, and what differs on 13.
license: MIT
---

# Nuke

Nuke loads, caches, and displays images on Apple platforms. What you remember about it is likely from 12.x or earlier, and much of it is out of date: delegate signatures changed, `LazyImage` plays GIFs again, and there's a new way to load into an image view. Follow this guide over your memory.

## Check the version first

```bash
grep -A6 '"identity" : "nuke"' Package.resolved
grep -A6 '"identity" : "nuke"' *.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
```

The guide describes Nuke 14. If the app is on 13.x, these differ:

| | Nuke 13 | Nuke 14 |
|---|---|---|
| Load into a `UIImageView` | `loadImage(with:into:)` from `NukeExtensions` | `ImageLoader.load(_:into:)` from `NukeUI` |
| GIF in `LazyImage` | Shows the first frame. Needs a third-party view | Plays with no setup |
| Parsed animation | None, use `ImageContainer.data` | `ImageContainer.animation` |
| `willCache` delegate method | Takes a `completion` closure | `async -> Data?` |
| A task starting, in the delegate | `.started` event | `imageTaskDidStart(_:pipeline:)` |
| Console log, `diagnostics`, `task.metrics` | None | See [Debugging](#debugging) |

To read the exact API of the version in use, look in the checkout. On Nuke 14 and later, `llms-full.txt` has the documentation and `llms-api.txt` every public signature, and the sources are there for any version:

- SwiftPM: `.build/checkouts/Nuke/`
- Xcode: `~/Library/Developer/Xcode/DerivedData/<App>-<hash>/SourcePackages/checkouts/Nuke/`

Online, the same files are at <https://raw.githubusercontent.com/kean/Nuke/main/llms.txt>.

## Which API to use

| You need | Use | Module |
|---|---|---|
| An image in SwiftUI | `LazyImage` | NukeUI |
| An image in a `UIImageView` or `NSImageView`, including in cells | `ImageLoader.load(_:into:)` | NukeUI |
| A UIKit view that owns its placeholder and failure states | `LazyImageView` | NukeUI |
| A GIF or another animated image | `LazyImage`, or `AnimatedImageView` with `ImageLoader` | NukeUI |
| An image in async code | `ImagePipeline.shared.image(for:)` | Nuke |
| Download progress or previews | `ImagePipeline.shared.imageTask(with:)` | Nuke |
| To load ahead of scrolling | `ImagePrefetcher` | Nuke |
| To draw your own SwiftUI view from the loading state | `FetchImage` | NukeUI |
| A short video | `NukeVideo` | NukeVideo |

`NukeUI` re-exports `Nuke`, so `import NukeUI` is enough. Don't use `NukeExtensions` in new code.

## SwiftUI

```swift
LazyImage(url: url) { state in
    if let image = state.image {
        image.resizable().scaledToFill()
    } else if state.error != nil {
        Image(systemName: "photo")
    } else {
        Color.secondary.opacity(0.2)
    }
}
.processors([.resize(width: 120)]) // The size it's displayed at
.frame(width: 120, height: 120)
.clipped()
```

`LazyImage(url:)` with no closure shows the image at its natural size, like `AsyncImage`. The closure gets the state, not a phase enum: `image`, `error`, `isLoading`, `progress`, `imageContainer`, `result`.

Other modifiers: `.priority(_:)`, `.pipeline(_:)`, `.onStart(_:)`, `.onCompletion(_:)`, and `.onDisappear(_:)`, which cancels by default. There's no `.onSuccess`, `.onFailure`, or `resizingMode`.

## UIKit and AppKit

```swift
ImageLoader.load(url, into: imageView, presentation: .init(
    placeholder: UIImage(named: "placeholder"),
    transition: .fadeIn(duration: 0.25),
    failureImage: UIImage(named: "error")
))
```

It's safe to call from `cellForItemAt`: a new load into a view cancels the previous one, so there's nothing to do in `prepareForReuse`. It takes a `URL?` or an `ImageRequest?`, and runs on the main actor. `ImageLoader.loader(for: imageView)` returns the loader, which has `processors`, `priority`, `keepsPreviousImage`, and `cancel()`.

## Animated images

Nothing needs to be enabled, and you never need to decode the frames yourself. `LazyImage` plays animations in its default content. A custom `content` closure has to do it, or it shows a still:

```swift
LazyImage(url: url) { state in
    if let container = state.imageContainer, let animation = AnimatedImage(container: container) {
        animation.resizable().scaledToFill()
    } else if let image = state.image {
        image.resizable().scaledToFill()
    } else {
        Color.secondary.opacity(0.2)
    }
}
```

In UIKit, a plain `UIImageView` shows a still, so use `AnimatedImageView`:

```swift
let imageView = AnimatedImageView()
imageView.contentMode = .scaleAspectFill
ImageLoader.load(url, into: imageView)
```

## Async

```swift
let task = ImagePipeline.shared.imageTask(with: url)
for await progress in task.progress {
    progressBar = progress // `fraction`, `completed`, `total`
}
image = try await task.image
```

A task starts the moment it's created. `task.previews` streams progressive previews, and `task.response` gives you the `ImageResponse`.

The errors are typed:

```swift
do {
    image = try await ImagePipeline.shared.image(for: url)
} catch {
    // `error` is an `ImagePipeline.Error`, no cast needed
    switch error {
    case .cancelled: break
    case .dataLoadingFailed(let underlying): print(underlying)
    default: print(error)
    }
}
```

## Setup

There is one pipeline in an app. Set it once at launch, and never create one per view: that throws away the caches and the deduplication of requests.

```swift
ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
```

By default, the pipeline has no `DataCache`, and relies on the `URLCache` of `DataLoader`, which follows the `cache-control` headers of the server. `.withDataCache` caches on disk whatever they say. To configure it yourself:

```swift
ImagePipeline.shared = ImagePipeline {
    $0.dataCache = try? DataCache(name: "com.example.images")
    $0.dataCachePolicy = .automatic
    $0.imageCache = ImageCache.shared
}
```

## Requests and processing

```swift
var request = ImageRequest(url: url, processors: [.resize(width: 320)], priority: .high)
request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 400) // Decodes small, without the full image
request.imageID = "avatar-42" // The cache key, for a URL with a changing token
request.options = [.disableDiskCacheWrites]
```

Resize to the size you display at, here or with `.processors`, not with a SwiftUI `.frame` alone: that keeps the full image in memory. The built-in processors are `.resize`, `.circle()`, `.roundedCorners(radius:)`, `.gaussianBlur(radius:)`, and `.coreImageFilter(name:)`. A custom one:

```swift
struct Sepia: ImageProcessing {
    let identifier = "com.example.sepia" // Part of the cache key

    func process(_ image: PlatformImage) -> PlatformImage? {
        ImageProcessors.CoreImageFilter(name: "CISepiaTone").process(image)
    }
}
```

## Prefetching

```swift
private let prefetcher = ImagePrefetcher()

func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
    prefetcher.startPrefetching(with: indexPaths.map { makeRequest(for: items[$0.item]) })
}

func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
    prefetcher.stopPrefetching(with: indexPaths.map { makeRequest(for: items[$0.item]) })
}

// The cells must load the same request, or the image is loaded twice
private func makeRequest(for item: Item) -> ImageRequest {
    ImageRequest(url: item.url, processors: [.resize(width: 120)])
}
```

## Caches

```swift
let pipeline = ImagePipeline.shared
let cached = pipeline.cache[url] // The memory cache, synchronously
pipeline.cache[request] = nil
pipeline.cache.removeCachedImage(for: request) // From every layer
pipeline.cache.removeAll()
ImageCache.shared.costLimit = 200 * 1024 * 1024
```

## The pipeline delegate

**A delegate method with the wrong signature compiles, and the pipeline never calls it.** Every method has a default implementation, so nothing tells you. Copy these signatures exactly, and declare the conformance in an extension, which is the only place the compiler warns about a method that nearly matches a requirement:

```swift
final class PipelineDelegate: Sendable {}

extension PipelineDelegate: ImagePipeline.Delegate {
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        var urlRequest = urlRequest
        urlRequest.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        request.url?.path.hasPrefix("/private/") == true ? nil : data // `nil` keeps it off the disk
    }

    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        nil // `nil` uses the default key
    }

    func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {}

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        switch event {
        case .progress(let progress): print(progress.fraction)
        case .preview(let response): print(response.image)
        case .finished(.failure(.cancelled)): break
        case .finished(let result): print(result)
        }
    }
}
```

The events are `.progress`, `.preview`, and `.finished`. There is no `.started` or `.cancelled`, and a cancelled task finishes with `.failure(.cancelled)`. The old `willCache(…completion:)` is the worst trap: it gets no warning, even in an extension.

Pass the delegate to the pipeline, and it has to be `Sendable`. `willCache` runs only if the pipeline has a disk cache, so it needs a `DataCache`:

```swift
ImagePipeline.shared = ImagePipeline(delegate: PipelineDelegate()) {
    $0.dataCache = try? DataCache(name: "com.example.images")
}
```

## Debugging

To find out why an image doesn't show up, don't add print statements. Launch the app with `NUKE_DIAGNOSTICS_LOG=1`, in the scheme, or with `SIMCTL_CHILD_NUKE_DIAGNOSTICS_LOG=1 xcrun simctl launch booted <bundle-id>`, and read one line per finished task. A line names the URL, and what came back:

```bash
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.github.kean.Nuke.ImagePipeline"'
```

```
ImageTask #2 · failure · 2.4 ms · decodingFailed · Failed to decode image data using decoder Nuke.ImageDecoders.Default. Received 60 bytes of text/html (HTTP 200) from https://example.com/b.jpg?…, starting with "<!DOCTYPE html><html><body>Sign".
```

No line at all means that no task reached this pipeline: the URL is `nil`, or a different pipeline is in use.

For a task that doesn't finish, stop in the debugger and read the state of the pipeline. It works with diagnostics off:

```
(lldb) po ImagePipeline.shared.diagnostics
```

In code:

```swift
let pipeline = ImagePipeline { $0.isDiagnosticsEnabled = true }
let task = pipeline.imageTask(with: url)
_ = try await task.image
print(task.metrics!) // A timeline of the load

print(await ImagePipeline.shared.diagnostics.snapshot())
```

`Documentation/Nuke.docc/Essentials/troubleshooting.md` in the checkout maps each failure to its cause.

## Tests and previews

Replace the data loader, and give the pipeline no shared caches:

```swift
/// Serves the same data for every request, with no network.
final class StubDataLoader: DataLoading {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        didReceiveData(data, URLResponse(url: request.url!, mimeType: nil, expectedContentLength: data.count, textEncodingName: nil))
        completion(nil)
        return StubTask()
    }

    private struct StubTask: Cancellable {
        func cancel() {}
    }
}
```

```swift
let pipeline = ImagePipeline {
    $0.dataLoader = StubDataLoader(data: data)
    $0.imageCache = nil // Or an `ImageCache()` of its own, so tests don't share one
    $0.dataCache = nil
}
```

Pass it to the view under test, not to `ImagePipeline.shared`:

```swift
LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    .pipeline(pipeline) // Only this view; `ImagePipeline.shared` is left alone
```

## Mistakes that compile

- A new `ImagePipeline` per view or per request.
- `.resizable()` on a large image with no processor, which keeps the full image in memory.
- A `UIImageView` or a custom `content` closure for a GIF, which shows a still.
- A prefetcher and a cell that build different requests, so the image is loaded twice.
- `LazyImage(url:).animation(.default)`, which is SwiftUI's modifier and does nothing for the load. Pass `transaction: Transaction(animation: .default)` to the initializer.
- `.processors(nil)` and `.priority(nil)` on `LazyImage`, which keep the request's value on Nuke 14. Pass `[]` to remove the processors.
