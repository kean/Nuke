# Image Decoding

## ``ImageDecoding`` Protocol

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

``ImageContainer`` is a struct that wraps the decoded image itself along with (optionally) the original data and some additional information. The decoder decides what to attach to the container.

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

To register the decoders, use ``ImageDecoderRegistry``. There are two ways to register the decoder.

The preferred approach is to make sure your decoders implement ``ImageDecoderRegistering`` protocol.

```swift
/// An image decoder which supports automatically registering in the decoder register.
public protocol ImageDecoderRegistering: ImageDecoding {
    /// Returns non-nil if the decoder can be used to decode the given data.
    ///
    /// - parameter data: The same data is going to be delivered to decoder via
    /// `decode(_:)` method. The same instance of the decoder is going to be used.
    init?(data: Data, context: ImageDecodingContext)

    /// Returns non-nil if the decoder can be used to progressively decode the
    /// given partially downloaded data.
    ///
    /// - parameter data: The first and the next data chunks are going to be
    /// delivered to the decoder via `decodePartiallyDownloadedData(_:)` method.
    init?(partiallyDownloadedData data: Data, context: ImageDecodingContext)
}

public extension ImageDecoderRegistering {
    /// The default implementation which simply returns `nil` (no progressive
    /// decoding available).
    init?(partiallyDownloadedData data: Data, context: ImageDecodingContext) {
        return nil
    }
}
```

By default, the registry is initialized with a single registered decoder, the default one:

```swift
public final class ImageDecoderRegistry {
    public init() {
        self.register(ImageDecoders.Default.self)
    }
}
```

If for some reason ``ImageDecoderRegistering`` does not work for you, use another ``ImageDecoderRegistry/register(_:)-8diym`` variant:

```swift
// Note: ImageDecoders.SVG not included in the framework.
ImageDecoderRegistry.shared.register { context: ImageDecodingContext in
    // Replace this with whatever works for. There are no magic numbers
    // for SVG like are used for other binary formats, it's just XML.
    let isSVG = context.urlResponse?.url?.absoluteString.hasSuffix(".svg") ?? false
    return isSVG ? ImageDecoders.SVG() : nil
}
```

> To determine image type, use an ``ImageType`` initializer that takes data as input. ``ImageType`` represents uniform type identifiers or UTI.

When you register a decoder, you have access to the entire decoding context for the given decoding session:

```swift
public struct ImageDecodingContext {
    public let request: ImageRequest
    public let data: Data
    public let urlResponse: URLResponse?
}
```

## Rendering Engines

The decoders in Nuke work at download time - regular decoders produce images as data arrives, while progressive decoders can produce multiple previews before delivering the final images. There are, however, scenarios when decoding at download time doesn't work: for example, for animated images.

For animated images, it is not feasible to decode all of the frames and put them in memory as bitmaps at download time – it will just consume too much memory. You have to postpone decoding to rendering time. When the image is displayed, a rendering engine, like [Gifu](https://github.com/kaishin/Gifu) or others, will decode and cache image frames on demand.

> GIF is not an efficient format. It is recommended to use short MP4 clips instead. See [Nuke Demo](https://github.com/kean/NukeDemo) for an example.

