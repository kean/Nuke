# Image View Extensions

Learn about extensions for image views.

## Overview

NukeUI provides a set of global functions that simplify loading of images into image views. It's a good starting point for some apps, but if you want to have more control, consider using ``LazyImageView`` or `ImagePipeline` directly.

> Tip: These functions were part of the separate `NukeExtensions` module before Nuke 14.

## Image View

Download and display an image in an image view with a single line of code:

```swift
NukeUI.loadImage(with: url, into: imageView)
```

If the image is stored in the memory cache, it is displayed immediately with no animations. If not, the image is first loaded using an image pipeline.

## Table View

Before loading a new image, the view is prepared for reuse by canceling any outstanding requests and removing a previously displayed image, making it perfect for table views.

```swift
func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    // ...
NukeUI.loadImage(with: url, into: cell.imageView)
}
```

What works for `UITableView`, also does for a `UICollectionView`. You can see `UICollectionView` in action in the [demo project](https://github.com/kean/NukeDemo).

> When the view is deallocated, an associated request also gets canceled automatically. To manually cancel the request, call ``NukeUI/cancelRequest(for:)``.

## ImageLoadingOptions

``ImageLoadingOptions`` offers multiple options to control the image view extensions behavior.

```swift
let options = ImageLoadingOptions(
    placeholder: UIImage(named: "placeholder"),
    transition: .fadeIn(duration: 0.33)
)
NukeUI.loadImage(with: url, options: options, into: imageView)
```

> Tip: The extensions have a limited set of options. If you need more, use ``LazyImageView``.

### Placeholder

Placeholder to be displayed while the image is loading. `nil` by default.

```swift
options.placeholder = UIImage(named: "placeholder")
```

### Failure Image

Image to be displayed when the request fails. `nil` by default.

```swift
option.failureImage = UIImage(named: "oopsie")
```

### Transitions

The image transition animation performed when displaying a loaded image. Only runs when the image was not found in the memory cache (use ``ImageLoadingOptions/alwaysTransition``) to always run the animation). `nil` by default.

```swift
options.transition = .fadeIn(duration: 0.33)
```

For a complete list of available transitions see ``ImageLoadingOptions/Transition-swift.struct``. Use ``ImageLoadingOptions/failureImageTransition`` for the failure image.

### Content Modes

You can change content mode for each of the image types: placeholder, success, failure. This is useful when a placeholder image needs to be displayed with `.center`, but image with `.scaleAspectFill`. By default, `nil` – don't change the content mode.

```swift
options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .center)
```

### Tint Colors

You can also specify custom tint colors to be used for each image type: placeholder, success, failure.

```swift
options.tintColors = .init(success: .green, failure: .red, placeholder: .yellow)
```

### Shared Options

If you want to modify the default options, set ``ImageLoadingOptions/shared``.

```swift
ImageLoadingOptions.shared.transition = .fadeIn(duration: 0.33)
```

### Other Options

For a complete list of options, see ``ImageLoadingOptions``. Some options, such as ``ImageLoadingOptions/isProgressiveRenderingEnabled`` will be covered later.

> Built-in extensions for image views are designed to get you up and running as quickly as possible. If you want more control, use ``ImagePipeline`` directly.

> Tip: To play animated images, load them into an ``AnimatedImageView`` instead of a plain `UIImageView` – everything else stays the same. See <doc:AnimatedImages>.

## Progressive Decoding

Progressive JPEG is supported out of the box.

## Custom Views

You can use image view extensions with custom views by implementing the ``ImageDisplaying`` protocol. The view is handed the whole `ImageContainer`, so it has everything the pipeline produced: the still image, the encoded `data`, and the `animation` parsed out of it.

```swift
final class MyImageView: UIView, ImageDisplaying {
    func nuke_display(_ container: ImageContainer?) {
        guard let animation = container?.animation else {
            return show(still: container?.image)
        }
        myEngine.play(animation)
    }
}
```

The module provides built-in implementations for `UIImageView` and `NSImageView`. ``AnimatedImageView`` is the one that plays animations, so reach for it before writing a renderer.

> Important: The built-in conformances come as extensions, and a Swift protocol conformance declared in an extension can't be overridden by a subclass. Conform your own view directly, as above, rather than subclassing `UIImageView` and overriding `nuke_display(_:)`.

## Customizing Requests

All the examples from this guide used ``NukeUI/loadImage(with:options:into:completion:)-(URL?,_,_,_)`` with a `URL`. But you can have even more control over the image download by using `ImageRequest`. To learn more about `ImageRequest`, see the main Nuke documentation.
