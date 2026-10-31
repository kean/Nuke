# UIKit and AppKit

Load images into UIImageView and NSImageView using ImageLoader from NukeUI.

## Overview

`ImageLoader` loads images into `UIImageView` and `NSImageView`, and into any other object that draws its state. It ships in NukeUI, in the same package as Nuke, so there is nothing extra to install – add the `NukeUI` library to your target and `import NukeUI`.

> Note: `ImageLoader` replaces the `loadImage(with:into:)` functions from `NukeExtensions`, which are soft-deprecated. They keep working, and the [migration guide](https://github.com/kean/Nuke/blob/main/Documentation/Migrations/Nuke%2014%20Migration%20Guide.md) maps their options to the new API.

## Loading Images into UIImageView

The most common use case is loading an image into a `UIImageView`.

```swift
import NukeUI

ImageLoader.load(url, into: imageView)
```

This uses ``ImagePipeline/shared`` and handles caching automatically. Starting a load is synchronous: an image found in the memory cache is displayed before `load` returns.

## Cell Reuse

The first load into a view attaches a loader to it. A new load into the same view cancels the previous one, and so does deallocating the view – so it's safe to call from `cellForItemAt` without extra bookkeeping.

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! ImageCell
    // Any previous load into this cell's imageView is cancelled automatically.
    ImageLoader.load(items[indexPath.item].imageURL, into: cell.imageView)
    return cell
}
```

## Placeholder and Failure Images

Pass an `ImageLoader.Presentation` to show a placeholder while the image loads and a failure image on error.

```swift
ImageLoader.load(url, into: imageView, presentation: .init(
    placeholder: UIImage(named: "placeholder"),
    failureImage: UIImage(named: "error")
))
```

## Transitions

Apply a cross-fade or a custom transition when the image loads. An image found in the memory cache is displayed without one.

```swift
ImageLoader.load(url, into: imageView, presentation: .init(
    transition: .fadeIn(duration: 0.3)
))
```

A presentation is a value, so define the ones your app uses once and pass them by name.

```swift
extension ImageLoader.Presentation {
    static let thumbnail = ImageLoader.Presentation(
        placeholder: UIImage(named: "placeholder"),
        transition: .fadeIn(duration: 0.25)
    )
}

ImageLoader.load(url, into: imageView, presentation: .thumbnail)
```

## Processors and Request Options

Pass an ``ImageRequest`` to apply processors or change request priority.

```swift
let request = ImageRequest(
    url: url,
    processors: [.resize(width: 320)]
)
ImageLoader.load(request, into: imageView)
```

The options that apply to every load into a view live on its loader, which `ImageLoader.loader(for:)` returns.

```swift
let loader = ImageLoader.loader(for: imageView)
loader.keepsPreviousImage = true
loader.priority = .high
```

## Awaiting the Outcome

`load` returns an `ImageLoader.Handle`. Await its `response` when you need the outcome.

```swift
let handle = ImageLoader.load(url, into: imageView)
Task {
    do {
        let response = try await handle.response
        print("Loaded image from: \(response.urlResponse?.url?.absoluteString ?? "cache")")
    } catch {
        print("Failed to load image: \(error)")
    }
}
```

The response of an image found in the memory cache is available right away. Cancelling the Swift task that awaits the response cancels the load, and a load replaced by a new one into the same view throws ``ImagePipeline/Error/cancelled``.

## Drawing the State Yourself

To display the image in something other than an image view – or to show a spinner or an error message next to it – pass a closure that draws the `ImageLoader.State`. It's called with every change of the state, including the ones made before `load` returns.

```swift
ImageLoader.load(url, into: cell) { cell, state in
    cell.posterView.image = state.image
    cell.spinner.isHidden = !state.isLoading
}
```

The target is held weakly and passed to the closure, so the closure doesn't need to capture it.

To keep the placeholder, the failure image, and the transitions of a `Presentation`, and change something else with the state, such as the content mode, call its `render(_:in:)` from the closure.

```swift
ImageLoader.load(url, into: imageView) { imageView, state in
    presentation.render(state, in: imageView)
    imageView.contentMode = state.image == nil ? .center : .scaleAspectFill
}
```

To receive the states in a delegate instead – the `event` of each state says what changed – create a loader and keep it.

```swift
final class PosterCell: UICollectionViewCell, ImageLoader.Delegate {
    private let loader = ImageLoader()
    private let posterView = UIImageView()
    private let progressView = UIProgressView()

    func configure(with url: URL) {
        loader.delegate = self
        loader.load(url)
    }

    func imageLoader(_ loader: ImageLoader, didUpdate state: ImageLoader.State) {
        posterView.image = state.image
        progressView.progress = state.progress.fraction
        progressView.isHidden = !state.isLoading
    }
}
```

> For the complete list of options, see `ImageLoader` in the [NukeUI documentation](https://kean-docs.github.io/nukeui/documentation/nukeui/). For a view that owns the loading states, see `LazyImageView`.
