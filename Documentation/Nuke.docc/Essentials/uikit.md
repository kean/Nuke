# UIKit and AppKit

Load images into UIImageView and NSImageView using the NukeUI module.

## Overview

NukeUI provides free functions for loading images into `UIImageView` and `NSImageView`. It ships in the same package as Nuke, so there is nothing extra to install – add the `NukeUI` library to your target and `import NukeUI`.

> Note: These functions were part of a separate `NukeExtensions` module before Nuke 14. That module still exists as a shim that re-exports `NukeUI`, but it's scheduled for removal in Nuke 15. See the [Nuke 14 Migration Guide](https://github.com/kean/Nuke/tree/main/Documentation/Migrations) for the details.

## Loading Images into UIImageView

The most common use case is loading an image into a `UIImageView`.

```swift
import NukeUI

NukeUI.loadImage(with: url, into: imageView)
```

This uses ``ImagePipeline/shared`` and handles caching automatically. The previous request for that image view is cancelled when a new one starts — so it's safe to call from `cellForItemAt` without extra bookkeeping.

## Cell Reuse

In collection and table views, cells are reused. Cancellation is handled automatically: starting a new `loadImage` call on a view cancels its previous request.

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! ImageCell
    // Any previous request on this cell's imageView is cancelled automatically.
    NukeUI.loadImage(with: items[indexPath.item].imageURL, into: cell.imageView)
    return cell
}
```

## Placeholder and Failure Images

Use `ImageLoadingOptions` to specify a placeholder shown while the image loads and a failure image shown on error.

```swift
var options = ImageLoadingOptions()
options.placeholder = UIImage(named: "placeholder")
options.failureImage = UIImage(named: "error")

NukeUI.loadImage(with: url, options: options, into: imageView)
```

## Transitions

Apply a cross-fade or a custom transition when the image loads.

```swift
var options = ImageLoadingOptions()
options.transition = .fadeIn(duration: 0.3)

NukeUI.loadImage(with: url, options: options, into: imageView)
```

To set a global default for all image views, configure `ImageLoadingOptions.shared`.

```swift
ImageLoadingOptions.shared.transition = .fadeIn(duration: 0.25)
```

## Processors and Request Options

Pass an ``ImageRequest`` to apply processors or change request priority.

```swift
let request = ImageRequest(
    url: url,
    processors: [.resize(width: 320)]
)
NukeUI.loadImage(with: request, into: imageView)
```

## Tracking Progress and Completion

Use the completion closure to respond to success or failure.

```swift
NukeUI.loadImage(with: url, into: imageView) { result in
    switch result {
    case .success(let response):
        print("Loaded image from: \(response.urlResponse?.url?.absoluteString ?? "cache")")
    case .failure(let error):
        print("Failed to load image: \(error)")
    }
}
```

## Custom Views

The extensions work with any view that conforms to `ImageDisplaying`, not just `UIImageView` and `NSImageView`.

```swift
final class MyImageView: UIView, ImageDisplaying {
    func nuke_display(_ container: ImageContainer?) {
        // Display `container?.image` however you like
    }
}
```

> For the complete list of options and the `LazyImageView` alternative, see the [NukeUI documentation](https://kean-docs.github.io/nukeui/documentation/nukeui/).
