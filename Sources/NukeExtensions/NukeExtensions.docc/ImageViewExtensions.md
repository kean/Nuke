# Image View Extensions

Nuke provides convenience extension for image views with multiple options to control the image view extensions behavior.

## Image View

Download and display an image in an image view with a single line of code:

```swift
Nuke.loadImage(with: url, into: imageView)
```

If the image is stored in the memory cache, it is displayed immediately with no animations. If not, the image is first loaded using an image pipeline.

> See <doc:image-pipeline-guide> to learn how images are downloaded and processed.

## Table View

Before loading a new image, the view is prepared for reuse by canceling any outstanding requests and removing a previously displayed image, making it perfect for table views.

```swift
func tableView(_ tableView: UITableView, cellForItemAt indexPath: IndexPaths) -> UITableViewCell {
    // ...
    Nuke.loadImage(with: url, into: cell.imageView)
}
```

What works for `UITableView`, also does for a `UICollectionView`. You can see `UICollectionView` in action in the [demo project](https://github.com/kean/NukeDemo).

> When the view is deallocated, an associated request also gets canceled automatically. To manually cancel the request, call ``Nuke/cancelRequest(for:)``.

## ImageLoadingOptions

``ImageLoadingOptions`` offers multiple options to control the image view extensions behavior.

```swift
let options = ImageLoadingOptions(
    placeholder: UIImage(named: "placeholder"),
    transition: .fadeIn(duration: 0.33)
)
Nuke.loadImage(with: url, options: options, into: imageView)
```

> The extensions have a limited set of options. If you need more, check out `LazyImageView` in [NukeUI](https://github.com/kean/NukeUI).

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
options.transition = .fadeIn(duration: 0.33))
```

For a complete list of available transitions see ``ImageLoadingOptions/Transition-swift.struct``. Use ``ImageLoadingOptions/failureImageTransition`` to failure image.

### Content Modes

You can change content mode for each of the image types: placeholder, success, failure. This is useful when a placeholder image needs to be displas with `.center`, but image with `.scaleAspectFill`. By default, `nil` – don't change the content mode.

```swift
options.contentModes = .init(success: .scaleAspectFill, failure: .center, placeholder: .center)
```

### Tint Colors

You can also specify a custom content modes to be used for each image type: placeholder, success, failure.

```swift
options.tintColors = .init(success: .green, failure: .red, placeholder: .yellow)
```

### Shared Options

If you want to modify the default options, set ``ImageLoadingOptions/shared``.

```swift
ImageLoadingOptions.shared.transition = .fadeIn(duration: 0.33))
```

### Other Options

For a complete list of options, see ``ImageLoadingOptions``. Some options, such as ``ImageLoadingOptions/isProgressiveRenderingEnabled`` will be covered later.

> Built-in extensions for image views are designed to get you up and running as quickly as possible. But if you want to have more control, or use some of the advanced features, like animated images, it is recommended to use ``ImagePipeline`` directly.

## Progressive Decoding

Nuke supports progressive JPEG out of the box.

## Custom Views

You can use image view extensions with custom views by implementing ``Nuke_ImageDisplaying`` protocol.

> The name of the protocol has a prefix because it's an Objective-C protocol. Objective-C runtime allows you to override methods declared in extensions in subclasses.

```swift
extension UIImageView: Nuke_ImageDisplaying {
    open func nuke_display(image: UIImage?, data: Data?) {
        self.image = image
    }
}
```

Nuke provides built-in implementations for `UIImageView`, `NSImageView`, and `WKInterfaceImage`.

## Customizing Requests

All the examples from this guide used ``Nuke/loadImage(with:options:into:progress:completion:)`` with a `URL`. But you can have even more control over the image download by using ``ImageRequest``. To learn more, see <doc:customizing-requests>.
