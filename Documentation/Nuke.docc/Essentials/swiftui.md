# SwiftUI

Display images in SwiftUI using the NukeUI module.

## Overview

[NukeUI](https://github.com/kean/NukeUI) is a companion module that provides SwiftUI components built on top of ``ImagePipeline``. Add it to your project via Swift Package Manager alongside Nuke.

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

Use the `content` closure to customize how each phase is displayed.

```swift
LazyImage(url: url) { phase in
    switch phase {
    case .success(let image):
        image.resizable().scaledToFill()
    case .failure:
        Image(systemName: "photo")
            .foregroundStyle(.secondary)
    case .empty:
        ProgressView()
    @unknown default:
        EmptyView()
    }
}
.frame(width: 320, height: 200)
.clipped()
```

## Transitions

Apply transitions to the displayed image using the `.transition` modifier.

```swift
LazyImage(url: url)
    .transition(.opacity)
```

For a cross-fade from a placeholder, use `.animation` on the phase view:

```swift
LazyImage(url: url) { phase in
    if let image = phase.image {
        image.resizable().scaledToFill()
    } else {
        Color.secondary.opacity(0.2)
    }
}
.animation(.easeInOut(duration: 0.3), value: phase.image != nil)
```

## Image Processors

Pass an ``ImageRequest`` to apply processors or set priority.

```swift
LazyImage(request: ImageRequest(
    url: url,
    processors: [.resize(width: 320)]
))
```

> Tip: Using `processors` ensures the resized image is stored in the memory cache at the display size, reducing memory pressure. See <doc:image-processing> to learn more.

## Using a Custom Pipeline

To use a pipeline other than ``ImagePipeline/shared``, pass it via the environment.

```swift
ContentView()
    .environment(\.imagePipeline, myPipeline)
```

All `LazyImage` views in that subtree will use `myPipeline` automatically.

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

`FetchImage` automatically cancels the in-flight request when the view disappears and restarts it when the view reappears.
