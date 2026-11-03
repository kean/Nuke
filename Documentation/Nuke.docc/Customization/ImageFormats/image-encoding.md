# Image Encoding

To encode images, use types conforming to the ``ImageEncoding`` protocol:

```swift
public protocol ImageEncoding: Sendable {
    /// Encodes the given image.
    func encode(_ image: PlatformImage) -> Data?

    /// An optional method which encodes the given image container.
    func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data?
}
```

There is currently no dedicated image encoder registry. Use the pipeline configuration to register custom encoders using ``ImagePipeline/Configuration-swift.struct/makeImageEncoder``.

An encoder writes a single image, so the default implementation of the second method returns the original data of an animated image – a GIF, an APNG, an animated WebP, or a HEIC or AVIF sequence – and encodes the image in every other case. A processed animation and a thumbnail of one are stills, and are encoded like any other image.

## Built-In Image Encoders

You can find all of the built-in encoders in the ``ImageEncoders`` namespace.

### ImageEncoders.Default

``ImageEncoders/Default`` encodes opaque images as `jpeg` and images with opacity as `png`. It can also be configured to use `heif` instead of `jpeg` using ``ImageEncoders/Default/isHEIFPreferred`` option.

### ImageEncoders.ImageIO

``ImageEncoders/ImageIO`` is an [Image I/O](https://developer.apple.com/documentation/imageio) based encoder.
 
Image I/O is a system framework that allows applications to read and write most image file formats. This framework offers high efficiency, color management, and access to image metadata.

```swift
let image: UIImage
let encoder = ImageEncoders.ImageIO(type: .heif, compressionRatio: 0.8)
let data = encoder.encode(image: image)
```
