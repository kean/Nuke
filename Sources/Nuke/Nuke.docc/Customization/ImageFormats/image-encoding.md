# Image Encoding

To encode images, use types conforming to the ``ImageEncoding`` protocol:

```swift
public protocol ImageEncoding {
    func encode(image: UIImage) -> Data?
}
```

There is currently no dedicated image encoder registry. Use the pipeline configuration to register a custom decoders using ``ImagePipeline/Configuration-swift.struct/makeImageDecoder``.

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
