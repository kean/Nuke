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

> Note: Unlike `AsyncImage`, `LazyImage` doesn't pass a phase enum to the closure – it passes the state itself, so you can read the download progress or the underlying ``ImageResponse`` while the view is on screen.

## Transitions

To animate the state changes, pass a `Transaction`. It's applied when the image is displayed.

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

You can also set them on the view, in which case they only apply if the request doesn't define its own.

```swift
LazyImage(url: url)
    .processors([.resize(width: 320)])
    .priority(.high)
```

> Tip: Using `processors` ensures the resized image is stored in the memory cache at the display size, reducing memory pressure. See <doc:image-processing> to learn more.

## Using a Custom Pipeline

To use a pipeline other than ``ImagePipeline/shared``, set it on the view.

```swift
LazyImage(url: url)
    .pipeline(myPipeline)
```

> Tip: There is no environment-based mechanism for this – `pipeline(_:)` is set per view. If most of your app uses a single custom pipeline, assign it to ``ImagePipeline/shared`` at launch instead of passing it to every view.

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
