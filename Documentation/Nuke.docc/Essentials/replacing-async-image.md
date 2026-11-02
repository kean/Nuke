# Replacing AsyncImage

Move from SwiftUI's `AsyncImage` to `LazyImage`, and learn what changes.

## Overview

`LazyImage` is shaped like `AsyncImage`: it takes a URL or a request, and a closure that builds the view for each state. The difference is where the image comes from. `AsyncImage` loads it with a `URLSession`. `LazyImage` loads it with an ``ImagePipeline``, so the image is cached in memory, a download that is already running is shared, the decoding happens off the main thread, and the request is canceled when the view goes away.

Most of the move is mechanical. Add `import NukeUI`, rename the view, and replace the `switch` on the phase with a check of the state.

## The Common Case

`AsyncImage` passes the closure a phase. `LazyImage` passes it the state, which has the same three outcomes as properties: `image` for `.success`, `error` for `.failure`, and neither for `.empty`.

```swift
// AsyncImage
AsyncImage(url: url) { phase in
    switch phase {
    case .success(let image):
        image.resizable().scaledToFill()
    case .failure:
        Image(systemName: "photo")
    case .empty:
        ProgressView()
    @unknown default:
        EmptyView()
    }
}

// LazyImage
LazyImage(url: url) { state in
    if let image = state.image {
        image.resizable().scaledToFill()
    } else if state.error != nil {
        Image(systemName: "photo")
    } else {
        ProgressView()
    }
}
```

The same goes for the form with a separate placeholder. There is no `placeholder` closure, so the `else` branch is the placeholder.

```swift
// AsyncImage
AsyncImage(url: url) { image in
    image.resizable()
} placeholder: {
    ProgressView()
}

// LazyImage
LazyImage(url: url) { state in
    if let image = state.image {
        image.resizable()
    } else {
        ProgressView()
    }
}
```

## Initializers

| AsyncImage | LazyImage |
|---|---|
| `AsyncImage(url:)` | `LazyImage(url:)` |
| `AsyncImage(url:scale:)` | Set `scale` on an ``ImageRequest``, as shown below |
| `AsyncImage(url:scale:content:placeholder:)` | `LazyImage(url:content:)`, with the placeholder in the `else` branch |
| `AsyncImage(url:scale:transaction:content:)` | `LazyImage(url:transaction:content:)` |
| `AsyncImage(request:)` and the other `request:` forms, on iOS 27 | `LazyImage(request:)` with ``ImageRequest/init(urlRequest:processors:priority:options:)``, from iOS 16 |
| `.asyncImageURLSession(_:)` | `.imagePipeline(_:)`, as shown below |
| `phase.image` | `state.image` |
| `phase.error` | `state.error` |

`AsyncImage` takes a `scale` because `Image` needs to know how many pixels make a point. `LazyImage` takes it from the request, and it is `1` by default, like the `scale` of `AsyncImage`.

```swift
var request = ImageRequest(url: url)
request.scale = 3

LazyImage(request: request) { state in
    if let image = state.image {
        image
    }
}
```

To load with the headers, the cache policy, or the timeout of a `URLRequest`, pass it to the request.

```swift
LazyImage(request: ImageRequest(urlRequest: urlRequest)) { state in
    if let image = state.image {
        image
    }
}
```

## Setting the Session

`asyncImageURLSession(_:)` sets the session that every `AsyncImage` below it loads with. `imagePipeline(_:)` does the same for `LazyImage`. Nuke builds the session itself, from the configuration of a ``DataLoader``, so that's where you put the headers, the timeouts, and the cache.

```swift
let configuration = DataLoader.defaultConfiguration
configuration.httpAdditionalHeaders = ["Authorization": "Bearer \(token)"]

let pipeline = ImagePipeline {
    $0.dataLoader = DataLoader(configuration: configuration)
}

ContentView()
    .imagePipeline(pipeline)
```

A pipeline set on a single view with `pipeline(_:)` takes precedence over the one in the environment. Without either, `LazyImage` loads with ``ImagePipeline/shared``. See <doc:loading-data> for the ways to customize how the data is loaded, including authentication challenges.

## Where the Behavior Differs

A view that is moved over compiles, but a few things work differently.

- **A missing URL is an error.** `LazyImage(url: nil)` doesn't stay in its loading state. It fails with ``ImagePipeline/Error/imageRequestMissing``, so `state.error` isn't `nil`. If a missing URL means that there is no image to show, check for it before you create the view.
- **The error has a type.** `state.error` is an ``ImagePipeline/Error``, and `AsyncImagePhase.failure` carries an `any Error`. Use the `dataLoadingFailed(error:)` case to get the error that `URLSession` reported.
- **Disappearing cancels the load.** The request is canceled when the view disappears, and it starts again when the view comes back. To change that, use `onDisappear(_:)`.

## Code That Takes a Phase

If your views take an `AsyncImagePhase`, for example a shared helper that draws every state in the same way, you don't have to rewrite them. Make a phase from the state.

```swift
extension LazyImageState {
    var phase: AsyncImagePhase {
        if let image {
            .success(image)
        } else if let error {
            .failure(error)
        } else {
            .empty
        }
    }
}

LazyImage(url: url) { state in
    AvatarContent(phase: state.phase)
}
```

## What You Get in Return

The phase has no room for most of what the pipeline knows, which is why the closure gets the state. Once you're on `LazyImage`, you can read `progress` and `isLoading`, set the `processors` and the `priority`, and play animated images. See <doc:swiftui> for the rest of `LazyImage`, <doc:image-processing> to resize an image to the size it is displayed at, and <doc:performance-guide> for the settings that matter in a list.
