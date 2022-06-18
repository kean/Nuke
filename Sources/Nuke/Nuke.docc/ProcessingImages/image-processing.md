# Image Processing

Learn how to use existing image filters and create custom ones.

## Overview

Nuke features a powerful and efficient image processing infrastructure with multiple built-in processors and an API for creating custom ones.

```swift
ImageRequest(url: url, processors: [
    .resize(size: imageView.bounds.size)
])
```

## ImageProcessors

The built-in processors can all be found in the ``ImageProcessors`` namespace, but the preferred way to create them is by using static factory methods on ``ImageProcessing`` protocol.

### Resize

To resize an image, use ``ImageProcessors/Resize``:

```swift
ImageRequest(url: url, processors: [
    .resize(size: imageView.bounds.size)
])
```

By default, the target size is in points. When the image is loaded, Nuke will downscale it to fill the target area, maintaining the aspect ratio. To crop the image, set `crop` to `true`. For more options, see ``ImageProcessors/Resize`` reference.

 ### Circle

``ImageProcessors/Circle`` rounds the corners of an image into a circle. It can also add a border.

```swift
ImageRequest(url: url, processors: [
    .circle()
])
```

### RoundedCorners

``ImageProcessors/RoundedCorners`` rounds the corners of an image to the specified radius.

```swift
ImageRequest(url: url, processors: [
    .roundedCorners(radius: 8)
])
```

> Important: Make sure to resize the image to match the size of the view in which it gets displayed so that the border appears correctly.

### GaussianBlur

``ImageProcessors/GaussianBlur`` blurs the input image using one of the [Core Image](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html) filters.

### CoreImageFilter

Apply any of the vast number [Core Image filters](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html) using ``ImageProcessors/CoreImageFilter`:

```swift
request.processors = [.coreImageFilter(name: "CISepiaTone")]
```

### Anonymous

For simple one-off operations, use ``ImageProcessors/Anonymous`` to create a processor with a closure.

```swift
ImageProcessors.Anonymous(id: "profile-icon") { image in
    // Perform processing operations...
}
```

## Custom Processors

Custom processors need to implement ``ImageProcessing`` protocol. For the basic image processing needs, implement ``ImageProcessing/process(_:)`` method and create an identifier that uniquely identifies the processor. For processors with no input parameters, return a static string.

```swift
public protocol ImageProcessing {
    func process(image: UIImage) -> UIImage? // NSImage on macOS
    var identifier: String { get }
}
```

> All processing tasks are executed on a dedicated queue (``ImagePipeline/Configuration-swift.struct/imageProcessingQueue``).

If your processor needs to manipulate image metadata (``ImageContainer``) or get access to more information via ``ImageProcessingContext``, there is an additional method that you can implement in addition to ``ImageProcessing/process(_:context:)-26ffb``.

```swift
public protocol ImageProcessing {
    func process(_ image container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer
}
```

In addition to ``ImageProcessing/identifier`` (a `String`), you can implement ``ImageProcessing/hashableIdentifier-2i3a7`` to be used by the memory cache where string manipulations would be too slow. By default, this method returns the `identifier` string. If your processor conforms to `Hashable` protocol, it gets a default ``ImageProcessing/hashableIdentifier-2i3a7`` implementation that returns `self`.

## Topics

### Image Processing

- ``ImageProcessing``
- ``ImageProcessingOptions``
- ``ImageProcessingContext``
- ``ImageProcessingError``


### Built-In Processors

- ``ImageProcessors``
