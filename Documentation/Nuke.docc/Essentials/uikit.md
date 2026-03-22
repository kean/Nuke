# UIKit and AppKit

Load images into UIImageView, NSImageView, and UIButton using the NukeExtensions module.

## Overview

[NukeExtensions](https://github.com/kean/NukeExtensions) is a companion module that provides free functions for loading images into `UIImageView`, `NSImageView`, and `UIButton`. Add it to your project via Swift Package Manager alongside Nuke.

## Loading Images into UIImageView

The most common use case is loading an image into a `UIImageView`.

```swift
import NukeExtensions

NukeExtensions.loadImage(with: url, into: imageView)
```

This uses ``ImagePipeline/shared`` and handles caching automatically. The previous request for that image view is cancelled when a new one starts — so it's safe to call from `cellForItemAt` without extra bookkeeping.

## Cell Reuse

In collection and table views, cells are reused. Nuke handles cancellation automatically: starting a new `loadImage` call on a view cancels its previous request.

```swift
func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! ImageCell
    // Any previous request on this cell's imageView is cancelled automatically.
    NukeExtensions.loadImage(with: items[indexPath.item].imageURL, into: cell.imageView)
    return cell
}
```

## Placeholder and Failure Images

Use `ImageLoadingOptions` to specify a placeholder shown while the image loads and a failure image shown on error.

```swift
var options = ImageLoadingOptions()
options.placeholder = UIImage(named: "placeholder")
options.failureImage = UIImage(named: "error")

NukeExtensions.loadImage(with: url, options: options, into: imageView)
```

## Transitions

Apply a cross-fade or a custom transition when the image loads.

```swift
var options = ImageLoadingOptions()
options.transition = .fadeIn(duration: 0.3)

NukeExtensions.loadImage(with: url, options: options, into: imageView)
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
NukeExtensions.loadImage(with: request, into: imageView)
```

## Tracking Progress and Completion

Use the completion closure to respond to success or failure.

```swift
NukeExtensions.loadImage(with: url, into: imageView) { result in
    switch result {
    case .success(let response):
        print("Loaded image from: \(response.urlResponse?.url?.absoluteString ?? "cache")")
    case .failure(let error):
        print("Failed to load image: \(error)")
    }
}
```

## Loading into UIButton

NukeExtensions also supports loading images into `UIButton`.

```swift
NukeExtensions.loadImage(with: url, into: button, for: .normal)
```

> For full NukeExtensions documentation, see the [NukeExtensions repository](https://github.com/kean/NukeExtensions) and its [documentation site](https://kean-docs.github.io/nukeextensions/documentation/nukeextensions/).
