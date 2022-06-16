# Image Formats

Nuke has built-in support for basic image formats like `jpeg`, `png`, and `heif`. It also has the infrastructure for supporting a variety of custom image formats.

Nuke is capable of driving progressive decoding, animated image rendering, progressive animated image rendering, drawing vector images directly or converting them to bitmaps, parsing thumbnails included in the image containers, and more.

## Image Decoding

### ImageDecoding Protocol

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

### Registering Decoders

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

### Rendering Engines

The decoders in Nuke work at download time - regular decoders produce images as data arrives, while progressive decoders can produce multiple previews before delivering the final images. There are, however, scenarios when decoding at download time doesn't work: for example, for animated images.

For animated images, it is not feasible to decode all of the frames and put them in memory as bitmaps at download time – it will just consume too much memory. You have to postpone decoding to rendering time. When the image is displayed, a rendering engine, like [Gifu](https://github.com/kaishin/Gifu) or others, will decode and cache image frames on demand.

> GIF is not an efficient format. It is recommended to use short MP4 clips instead. See [Nuke Demo](https://github.com/kean/NukeDemo) for an example.

## Built-In Image Decoders

You can find all of the built-in decoders in the [`ImageDecoders`](https://kean-org.github.io/docs/nuke/reference/10.2.0/ImageDecoders/) namespace.

### ImageDecoders.Default

``ImageDecoders/Default`` is used by default if no custom decoders are registered. It uses native `UIImage(data:)` (and `NSImage(data:)`) initializers to create images from data.

> When working with `UIImage`, the decoder automatically sets the scale of the image to match the scale of the screen.
{:.info}

The default ``ImageDecoders/Default`` also supports progressively decoding JPEG. It produces a new preview every time it encounters a new frame.

### ImageDecoders.Empty

``ImageDecoders/Empty`` returns an empty placeholder image and attaches image data to the image container. It could also be configured to return partially downloaded data. ``ImageDecoders/Empty`` can be used when the rendering engine works directly with image data.

## Image Encoding

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

## Supported Formats

### Common Image Formats

All images format [natively supported](https://developer.apple.com/library/archive/documentation/2DDrawing/Conceptual/DrawingPrintingiOS/LoadingImages/LoadingImages.html#//apple_ref/doc/uid/TP40010156-CH17-SW7) by the platform are also supported by Nuke, including `PNG`, `TIFF`, `JPEG`, `GIF`, `BMP`, `ICO`, `CUR`, and `XBM`.

You can use the basic `UIImageView`/`NSImageView`/`WKInterfaceImage` to render the images of any of the natively supported formats.

### Progressive JPEG

**Decoding**

``ImageDecoders/Default`` supports progressive JPEG. The decoder automatically detects when there are new scans available and produces new previews.

**Encoding**

None.

**Rendering**

To render the progressive JPEG, you can use the basic `UIImageView`/`NSImageView`/`WKInterfaceImage`. The default image view loading extensions also supports displaying progressive scans. 



### HEIF

**Decoding**

``ImageDecoders/Default`` supports [HEIF](https://en.wikipedia.org/wiki/High_Efficiency_Image_File_Format).

**Encoding**

``ImageEncoders/Default`` supports [HEIF](https://en.wikipedia.org/wiki/High_Efficiency_Image_File_Format) but doesn't use it by default. To enable it, use ``ImageEncoders/Default/isHEIFPreferred``.

You can use [`ImageEncoders.ImageIO`](https://kean-org.github.io/docs/nuke/reference/10.2.0/ImageEncoders_ImageIO/) directly:

```swift
let image: UIImage
let encoder = ImageEncoders.ImageIO(type: .heif, compressionRatio: 0.8)
let data = encoder.encode(image: image)
```

**Rendering**

To render HEIF images, you can use `UIImageView`/`NSImageView`/`WKInterfaceImage`.

### GIF

**Decoding**

``ImageDecoders/Default`` automatically recognizes GIFs. It creates an image container (``ImageContainer``) with the first frame of the GIF as a placeholder and attaches the original image data to the container so that you can perform just-in-time decoding at rendering time.

**Encoding**

None.

**Rendering**

To render animated GIFs, please consider using one of the open-source GIF rendering engines, like [Gifu](https://github.com/kaishin/Gifu), [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage), or other.

**Gifu Example**

```swift
/// A custom image view that supports downloading and displaying animated images.
final class ImageView: UIView {
    private let imageView: GIFImageView
    private let spinner: UIActivityIndicatorView
    private var task: ImageTask?

    /* Initializers skipped */

    func setImage(with url: URL) {
        prepareForReuse()

        if let response = ImagePipeline.shared.cachedResponse(for: url) {
            return imageView.display(response: response)
        }

        spinner.startAnimating()
        task = ImagePipeline.shared.loadImage(with: url) { [weak self] result in
            self?.spinner.stopAnimating()
            if case let .success(response) = result {
                self?.imageView.display(response: response)
            }
        }
    }
    
    private func display(response: ImageResponse) {
        if let data = response.container.data {
            animate(withGIFData: data)
        } else {
            image = response.image
        }
    }
    
    private func prepareForReuse() {
        task?.cancel()
        spinner.stopAnimating()
        imageView.prepareForReuse()
    }
}
```

To see this code in action, check out the [demo project](https://github.com/kean/NukeDemo).

> `GIF` is not the most efficient format for transferring and displaying animated images. Consider using [short videos instead](https://developers.google.com/web/fundamentals/performance/optimizing-content-efficiency/replace-animated-gifs-with-video/). You can find a PoC available in the [demo project](https://github.com/kean/NukeDemo) that uses Nuke to load, cache and display an `MP4` video.


### SVG

**Decoding**

There is currently no built-in support for SVG. Use ``ImageDecoders/Empty`` to pass the original image data to an SVG-enabled view and render is using an external mechanism.

**Encoding**

None.

**Rendering**

To render SVG, consider using [SwiftSVG](https://github.com/mchoe/SwiftSVG), [SVG](https://github.com/SVGKit/SVGKit), or other frameworks. Here is an example of `SwiftSVG` rendering vector images.

```swift
ImageDecoderRegistry.shared.register { context in
    // Replace this with whatever works for you. There are no magic numbers
    // for SVG like are used for other binary formats, it's just XML.
    let isSVG = context.urlResponse?.url?.absoluteString.hasSuffix(".svg") ?? false
    return isSVG ? ImageDecoders.Empty() : nil
}

let url = URL(string: "https://upload.wikimedia.org/wikipedia/commons/9/9d/Swift_logo.svg")
ImagePipeline.shared.loadImage(with: url) { [weak self] result in
    guard let self = self, let data = try? result.get().container.data else {
        return
    }
    // You can render image using whatever size you want, vector!
    let targetBounds = CGRect(origin: .zero, size: CGSize(width: 300, height: 300))
    let svgView = UIView(SVGData: data) { layer in
        layer.fillColor = UIColor.orange.cgColor
        layer.resizeToFit(targetBounds)
    }
    self.view.addSubview(svgView)
    svgView.bounds = targetBounds
    svgView.center = self.view.center
}
```

> Important: Both [SwiftSVG](https://github.com/mchoe/SwiftSVG) and [SVG](https://github.com/SVGKit/SVGKit) only support a subset of SVG features.

### WebP

#### Third-party Support

[WebP](https://developers.google.com/speed/webp) support is provided by [Nuke WebP Plugin](https://github.com/ryokosuge/Nuke-WebP-Plugin) built by [Ryo Kosuge](https://github.com/ryokosuge). Please follow the instructions from the repo.

#### Native Support (macOS 11, iOS 14, watchOS 7)

WebP is now supported natively. Nuke currently only supports baseline WebP (no progressive WebP support).
