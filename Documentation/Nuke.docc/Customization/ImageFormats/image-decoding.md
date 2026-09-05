# Image Decoding

## ImageDecoding Protocol

At the core of the decoding infrastructure is the ``ImageDecoding`` protocol.

```swift
public protocol ImageDecoding: Sendable {
    /// Returns `true` if you want the decoding to be performed on the
    /// decoding queue. If `false`, decoding is performed synchronously
    /// on the pipeline's actor. By default, `true`.
    var isAsynchronous: Bool { get }

    /// Produces an image from the given image data.
    func decode(_ data: Data) throws -> ImageContainer

    /// Produces an image from the given partially downloaded image data.
    /// This method might be called multiple times during a single decoding
    /// session. When the image download is complete, ``decode(_:)`` is called.
    ///
    /// - returns: nil by default.
    func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer?
}
```

``ImageContainer`` is a struct that wraps the decoded image and (optionally) the original data and some additional information. The decoder decides what to attach to the container.

```swift
public struct ImageContainer {
    /// Either `UIImage` or `NSImage`, depending on the platform.
    public var image: PlatformImage
    /// An image type.
    public var type: AssetType?
    /// Returns `true` if the image is a preview (progressive scan, thumbnail).
    public var isPreview: Bool
    /// Contains the original image data, but only if the decoder attaches it.
    public var data: Data?
    /// The animation the data describes, if the image is an animated one.
    public var animation: AnimatedImageSource?
    /// Metadata provided by the user.
    public var userInfo: [UserInfoKey: Any]
}
```

When the first chunk of the image data is loaded, ``ImagePipeline`` creates a decoder for the given image format.

The pipeline uses ``ImageDecoderRegistry`` to find the decoder.  The decoder is created once and is reused across a single image decoding session until the final chunk of data is downloaded. If the decoder supports progressive decoding, make it a `class` to retain state within a single decoding session.

> ``ImageDecoding/decode(_:)`` method only passes `data` to the decoder. If the decoder needs additional information, pass it when instantiating it. ``ImageDecodingContext`` provides everything that you might need, including the full ``ImageRequest``.
>
> You can also take advantage of ``ImageRequest/userInfo``. For example, you may pass the target image view size to the SVG decoder to let it know the size of the image to create.

The decoding is performed in the background on ``ImagePipeline/Configuration-swift.struct/imageDecodingQueue``. There is always only one decoding request at a time. The pipeline doesn't call ``ImageDecoding/decodePartiallyDownloadedData(_:)-9budu`` again until you are finished with the previous chunk.

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

The decoders are evaluated in the reverse order of registration: the most recently registered decoder is asked first. ``ImageDecoderRegistry/register(_:)`` returns a token that you can pass to ``ImageDecoderRegistry/unregister(_:)`` to remove the decoder, which is useful if a decoder is only needed for a part of the app's lifetime.

```swift
let token = ImageDecoderRegistry.shared.register(ImageDecoders.SVG.init)
ImageDecoderRegistry.shared.unregister(token)
```

## Animated Images

The decoders work at download time - regular decoders produce images as data arrives, while progressive decoders can produce multiple previews before delivering the final images. But there are scenarios when decoding at download time doesn't work: for example, for animated images.

For animated images, it is not feasible to decode all of the frames and put them in memory as bitmaps at download time – it will consume too much memory. Decoding has to be postponed to rendering time, where a player decodes the frames on demand and keeps only a few of them around.

``ImageDecoders/Default`` prepares for that in two ways. It attaches the encoded data to the images it recognizes as animated – ``ImageContainer/data`` is all that a third-party engine like [Gifu](https://github.com/kaishin/Gifu) needs – and beside it an ``AnimatedImageSource``, which is what says how many frames there are, how long each one is shown, how many times the animation repeats, and how large its canvas is. Reading that costs a scan of the container and not a decoded pixel. `NukeUI` plays it – see [Animated Images](https://kean-docs.github.io/nukeui/documentation/nukeui/animatedimages).

> GIF is not an efficient format. It is recommended to use short MP4 clips instead, which `NukeVideo` plays.

### Adding an Animated Format

An animated format is added the way any other format is: an ``ImageDecoding`` registered with ``ImageDecoderRegistry``. What makes it animated is what the decoder attaches to the container – an ``AnimatedImageSource`` describing the animation, and, handed over with it, what produces the frames.

```swift
ImageDecoderRegistry.shared.register(WebPDecoder.init(context:))

struct WebPDecoder: ImageDecoding {
    init?(context: ImageDecodingContext) {
        guard context.isCompleted, AssetType(context.data) == .webp else {
            return nil // Not this format, or not all of it yet
        }
    }

    func decode(_ data: Data) throws -> ImageContainer {
        let webp = try WebPImage(data: data) // A codec of your own
        var container = ImageContainer(image: webp.makeFirstFrame())
        container.data = data
        container.animation = AnimatedImageSource(
            data: data,
            delays: webp.delays,
            loopCount: webp.loopCount,
            size: webp.size,
            makeFrameDecoder: { WebPFrameDecoder(webp, maxPixelSize: $0) }
        )
        return container
    }
}
```

This is the initializer to reach for whether or not Image I/O can read the format: ``AnimatedImageSource/init(data:)`` parses the container with Image I/O and returns `nil` for anything it can't open, so a codec the system doesn't have has no other door. The still image the container carries is the decoder's too – it holds the place until the first frame is decoded.

The frames themselves come from an ``AnimatedImageFrameDecoding``, which is one method:

```swift
actor WebPFrameDecoder: AnimatedImageFrameDecoding {
    init(_ image: WebPImage, maxPixelSize: CGFloat?) { ... }

    func decode(at index: Int) -> CGImage? { ... }
}
```

A few things are worth knowing about how it is used:

- **It is asked for one frame at a time, in playback order**, and stops being asked when the player's window of frames is full. Returning `nil` is remembered: a frame the decoder refuses is not asked for again, so a truncated animation plays the frames it has.
- **It is made once per animation and size** – when the first view showing the animation needs a frame – and released with the last view. A decoder holds the container it reads from, which costs about what a decoded frame does, so that is where the indexing belongs, not in the closure that makes it.
- **`maxPixelSize` is the longest side, in pixels, the frames are wanted at**, or `nil` for the size the animation is stored at. It comes from `AnimatedImagePlayer.Options.maxPixelSize`, and a decoder is expected to honor it: the player has budgeted memory for frames of that size.
- **The player is on the main actor and awaits the frames.** Produce them on an actor or a queue of your own; an implementation isolated to the main actor decodes on it. An `actor`, as above, is the shape that gets this right by default.

The frame count comes from `delays.count`, and the delays are corrected the same way the ones read from a container are: a missing or non-positive delay becomes 0.1 s, and so does a delay below 0.011 s. ``AnimatedImageSource/init(data:delays:loopCount:size:makeFrameDecoder:)`` returns `nil` for a single frame or an empty canvas, neither of which is something to play – attach nothing in that case and let the still image stand on its own.

Everything downstream is unchanged. The frames a decoder of your own produces are decoded off the main thread, windowed, shared between every view showing the animation, and counted against the same memory budget as Image I/O's.

## Built-In Image Decoders

You can find all of the built-in decoders in the ``ImageDecoders`` namespace.

### ImageDecoders.Default

``ImageDecoders/Default`` is used by default if no custom decoders are registered. It uses native `UIImage(data:)` (and `NSImage(data:)`) initializers to create images from data.

The default ``ImageDecoders/Default`` also supports progressive decoding via `CGImageSourceCreateIncremental`. It produces previews as data arrives, gated by ``ImagePipeline/PreviewPolicy`` (`.incremental` for progressive JPEGs and GIFs by default, `.disabled` for other formats).

### ImageDecoders.Video 

Generates a video preview and attaches downloaded data to the image container.

### ImageDecoders.Empty

``ImageDecoders/Empty`` returns an empty placeholder image and attaches image data to the image container. It could also be configured to return partially downloaded data. ``ImageDecoders/Empty`` can be used when the rendering engine works directly with image data.
