# SwiftUI

Display images in SwiftUI using the NukeUI module.

## Overview

NukeUI provides SwiftUI components built on top of ``ImagePipeline``. It ships in the same package as Nuke, so there is nothing extra to install – add the `NukeUI` library to your target and `import NukeUI`.

## LazyImage

`LazyImage` is the primary view for displaying remote images in SwiftUI. It loads and displays an image from a URL, handling the full lifecycle: loading, displaying, and caching.

```swift
import NukeUI

struct AvatarView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url)
            .frame(width: 80, height: 80)
            .clipShape(Circle())
    }
}
```

`LazyImage` uses ``ImagePipeline/shared`` by default and inherits all of its caching behavior.

> Note: The default content – `LazyImage(url:)` with no closure – displays the image at its natural size, just like `AsyncImage`. Use the `content` closure to make it resizable.

## Handling Loading and Failure States

Use the `content` closure to customize what is displayed for each state. The closure receives a `LazyImageState` with `image`, `error`, `isLoading`, `progress`, and the underlying `result`.

```swift
LazyImage(url: url) { state in
    if let image = state.image {
        image.resizable().scaledToFill()
    } else if state.error != nil {
        Image(systemName: "photo")
            .foregroundStyle(.secondary)
    } else {
        ProgressView()
    }
}
.frame(width: 320, height: 200)
.clipped()
```

> Note: Unlike `AsyncImage`, `LazyImage` doesn't pass a phase enum to the closure – it passes the state itself, so you can read the download progress or the underlying ``ImageResponse`` while the view is on screen. See <doc:replacing-async-image> if you're moving from `AsyncImage`.

To keep the failure out of the `content` closure, or to add it to the default content, use `failureView(_:)`. It receives the same state.

```swift
LazyImage(url: url)
    .failureView { state in
        Button("Retry") { state.reload() }
    }
```

## Reloading

`reload()` on the state loads the image again from inside of the view, as in the sample above. To do it from outside, pass a value to `reload(id:)`, and change it.

```swift
struct RetryingView: View {
    let url: URL
    @State private var attempt = 0

    var body: some View {
        LazyImage(url: url)
            .reload(id: attempt)
        Button("Retry") { attempt += 1 }
    }
}
```

Either way, the view stays and only the load starts over. A load that is still running keeps running, and an image in the memory cache is displayed without a download. To skip the caches, load a request with ``ImageRequest/Options-swift.struct/reloadIgnoringCachedData``.

> Tip: Don't use `id(_:)` to reload. A new identity throws away the view and everything it knows, so the placeholder is back for as long as the load takes.

## Keeping the Previous Image

When the request changes, `LazyImage` clears the image and displays the placeholder until the new one is ready. To replace the image in place instead, for example in a detail view that pages through photos, use `keepsPreviousImage(_:)`. The previous image is dropped if the new load fails.

```swift
LazyImage(url: url)
    .keepsPreviousImage()
```

## Transitions

To run a transition when an image is displayed, use `imageTransition(_:animation:onMemoryCacheHit:)`. It doesn't depend on how the `content` closure is written, so it works with the default content too.

```swift
LazyImage(url: url)
    .imageTransition(.opacity, animation: .easeInOut(duration: 0.33))
```

An image in the memory cache is displayed with no transition, so that a list doesn't run it for every cell that scrolls back. Pass `onMemoryCacheHit: true` to run it anyway. Combined with `keepsPreviousImage(_:)`, it also runs between two images, which makes `.opacity` a cross-fade.

To animate the state changes that your own `content` closure makes, pass a `Transaction` instead. It's applied when the image is displayed.

```swift
LazyImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.33))) { state in
    if let image = state.image {
        image.resizable().scaledToFill()
    } else {
        Color.secondary.opacity(0.2)
    }
}
```

## Image Processors

Pass an ``ImageRequest`` to apply processors or set priority.

```swift
LazyImage(request: ImageRequest(
    url: url,
    processors: [.resize(width: 320)]
))
```

You can also set them on the view, in which case they replace the ones the request defines.

```swift
LazyImage(url: url)
    .processors([.resize(width: 320)])
    .priority(.high)
```

> Tip: Using `processors` ensures the resized image is stored in the memory cache at the display size, reducing memory pressure. See <doc:image-processing> to learn more.

## Using a Custom Pipeline

To use a pipeline other than ``ImagePipeline/shared``, set it on the view hierarchy. Every `LazyImage` below the modifier loads with it, the way `asyncImageURLSession(_:)` sets the session of `AsyncImage`.

```swift
ContentView()
    .imagePipeline(myPipeline)
```

A pipeline set on a single view with `pipeline(_:)` takes precedence over the one in the environment.

```swift
LazyImage(url: url)
    .pipeline(myPipeline)
```

Changing the pipeline reloads the images that are on screen. If your whole app uses a single custom pipeline, you can also assign it to ``ImagePipeline/shared`` at launch.

## FetchImage for Custom Views

`FetchImage` is an `ObservableObject` that gives you full control of the loading lifecycle. Use it when you need to drive your own custom view.

```swift
struct CustomImageView: View {
    let url: URL
    @StateObject private var fetchImage = FetchImage()

    var body: some View {
        ZStack {
            fetchImage.image?
                .resizable()
                .scaledToFill()

            if fetchImage.isLoading {
                ProgressView()
            }
        }
        .onAppear { fetchImage.load(url) }
        .onDisappear { fetchImage.reset() }
    }
}
```

`reset()` cancels the in-flight request and clears the loaded image. Use `cancel()` instead if you want to stop the download but keep displaying what was already loaded.
