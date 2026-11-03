# Image Processing

Learn how to use existing image filters and create custom ones.

## Overview

The pipeline has a powerful and efficient image processing infrastructure with multiple built-in processors and an API for creating custom ones.

```swift
ImageRequest(url: url, processors: [
    .resize(size: imageView.bounds.size)
])
```

The built-in processors can all be found in the ``ImageProcessors`` namespace, but the preferred way to create them is by using static factory methods on ``ImageProcessing`` protocol.

## Cropping, Flipping, and Rotating

Use ``ImageProcessing/crop(rect:unit:)``, ``ImageProcessing/flip(_:)``, and ``ImageProcessing/rotate(degrees:)`` to change the geometry of an image.

```swift
ImageRequest(url: url, processors: [
    .crop(rect: CGRect(x: 0, y: 0, width: 1200, height: 630), unit: .pixels),
    .rotate(degrees: 90),
    .flip(.horizontal)
])
```

These act on the image as it's displayed, so a rectangle is measured from the top-left corner of a photo even if the file stores it on its side. Processors run in order, so each one gets the output of the one before it.

- A crop ignores the part of the rectangle outside of the image, and fails the request if nothing is left.
- A rotation is clockwise. A multiple of 90 degrees moves the pixels without resampling them. Any other angle grows the canvas to fit the rotated image and leaves the corners transparent, so the output has an alpha channel even if the input was opaque.

## Tinting

``ImageProcessing/tint(color:)`` paints a color over an image with the `sourceAtop` blend mode, which keeps the alpha of the image. An opaque color turns it into a silhouette, which is the way to color a template icon. A translucent one is laid over it, which is the way to darken a photo under some text.

```swift
ImageRequest(url: url, processors: [
    .tint(color: .black.withAlphaComponent(0.4))
])
```

## Custom Processors

Custom processors need to implement ``ImageProcessing`` protocol. For the basic image processing needs, implement ``ImageProcessing/process(_:)`` method and create an identifier that uniquely identifies the processor. For processors with no input parameters, return a static string.

```swift
public protocol ImageProcessing {
    func process(_ image: PlatformImage) -> PlatformImage?
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
- ``ImageProcessing/crop(rect:unit:)``
- ``ImageProcessing/flip(_:)``
- ``ImageProcessing/rotate(degrees:)``
- ``ImageProcessing/tint(color:)``
- ``ImageProcessing/gaussianBlur(radius:)``
- ``ImageProcessing/coreImageFilter(name:)``
- ``ImageProcessing/coreImageFilter(name:parameters:identifier:)``
- ``ImageProcessing/process(id:_:)``
- ``ImageProcessors``
