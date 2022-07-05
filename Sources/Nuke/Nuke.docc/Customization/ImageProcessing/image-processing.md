# Image Processing

Learn how to use existing image filters and create custom ones.

## Overview

Nuke features a powerful and efficient image processing infrastructure with multiple built-in processors and an API for creating custom ones.

```swift
ImageRequest(url: url, processors: [
    .resize(size: imageView.bounds.size)
])
```

The built-in processors can all be found in the ``ImageProcessors`` namespace, but the preferred way to create them is by using static factory methods on ``ImageProcessing`` protocol.

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

- ``ImageProcessing/resize(size:unit:contentMode:crop:upscale:)``
- ``ImageProcessing/resize(width:unit:upscale:)``
- ``ImageProcessing/resize(height:unit:upscale:)``
- ``ImageProcessing/circle(border:)``
- ``ImageProcessing/roundedCorners(radius:unit:border:)``
- ``ImageProcessing/gaussianBlur(radius:)``
- ``ImageProcessing/coreImageFilter(name:)``
- ``ImageProcessing/coreImageFilter(name:parameters:identifier:)``
- ``ImageProcessing/process(id:_:)``
- ``ImageProcessors``
