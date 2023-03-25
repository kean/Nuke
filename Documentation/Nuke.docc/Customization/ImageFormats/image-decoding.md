# Image Decoding

## ImageDecoding Protocol

At the core of the decoding infrastructure is the ``ImageDecoding`` protocol.

```swift
public protocol ImageDecoding {
    /// Produces an image from the given image data.
    func decode(_ data: Data) -> ImageContainer?

    /// Produces an image from the given partially downloaded image data.
    /// This method might be called multiple times during a single decoding
    /// session. When the image download is complete, `decode(data:)` method is called.
    ///
    /// - returns: nil by default.
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer?
}
```

``ImageContainer`` is a struct that wraps the decoded image and (optionally) the original data and some additional information. The decoder decides what to attach to the container.

```swift
public struct ImageContainer {
    // Either `UIImage` or `NSImage` depending on the platform.
    public let image: UIImage
    public let data: Data?
    public let userInfo: [AnyHashable: Any]
}
```

When the first chunk of the image data is loaded, ``ImagePipeline`` creates a decoder for the given image format.

The pipeline uses ``ImageDecoderRegistry`` to find the decoder.  The decoder is created once and is reused across a single image decoding session until the final chunk of data is downloaded. If the decoder supports progressive decoding, make it a `class` to retain state within a single decoding session.

> ``ImageDecoding/decode(_:)`` method only passes `data` to the decoder. If the decoder needs additional information, pass it when instantiating it. ``ImageDecodingContext`` provides everything that you might need.
>
> You can also take advantage of ``ImageRequest/userInfo``. For example, you may pass the target image view size to the SVG decoder to let it know the size of the image to create.  

The decoding is performed in the background on the operation queue provided in ``ImagePipeline/Configuration-swift.struct``. There is always only one decoding request at a time. The pipeline doesn't call ``ImageDecoding/decodePartiallyDownloadedData(_:)-9budu`` again until you are finished with the previous chunk.

## Registering Decoders

To register the decoders, use ``ImageDecoderRegistry``.

```swift
func register() {
    ImageDecoderRegistry.shared.register(ImageDecoders.SVG.init)
}

extension ImageDecoders {
    final class SVG: ImageDecoding {
        init?(context: ImageDecodingContext) {
            guard context.isCompleted else {
                return nil // No progressive decoding
            }

            let isSVG = context.urlResponse?.url?.absoluteString.hasSuffix(".svg") ?? false
            guard isSVG else {
                return nil // Image format isn't supported.
            }   
        }
    }
}
```

> Tip: To determine image type, use an ``AssetType`` initializer that takes data as input. ``AssetType`` represents uniform type identifiers or UTI.

When you register a decoder, you have access to ``ImageDecodingContext`` for the given decoding session.

## Rendering Engines

The decoders in Nuke work at download time - regular decoders produce images as data arrives, while progressive decoders can produce multiple previews before delivering the final images. But there are scenarios when decoding at download time doesn't work: for example, for animated images.

For animated images, it is not feasible to decode all of the frames and put them in memory as bitmaps at download time – it will consume too much memory. You have to postpone decoding to rendering time. When the image is displayed, a rendering engine, like [Gifu](https://github.com/kaishin/Gifu) or others, will decode and cache image frames on demand.

> GIF is not an efficient format. It is recommended to use short MP4 clips instead. See [Nuke Demo](https://github.com/kean/NukeDemo) for an example.

## Built-In Image Decoders

You can find all of the built-in decoders in the ``ImageDecoders`` namespace.

### ImageDecoders.Default

``ImageDecoders/Default`` is used by default if no custom decoders are registered. It uses native `UIImage(data:)` (and `NSImage(data:)`) initializers to create images from data.

> When working with `UIImage`, the decoder automatically sets the scale of the image to match the scale of the screen.

The default ``ImageDecoders/Default`` also supports progressively decoding JPEG. It produces a new preview every time it encounters a new frame.

### ImageDecoders.Video 

Generates a video preview and attaches downloaded data to the image container.

### ImageDecoders.Empty

``ImageDecoders/Empty`` returns an empty placeholder image and attaches image data to the image container. It could also be configured to return partially downloaded data. ``ImageDecoders/Empty`` can be used when the rendering engine works directly with image data.
