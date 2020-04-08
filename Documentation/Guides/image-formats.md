# Image Formats

Nuke offers built-in support for basic image formats like `jpeg`, `png`, and `heif`. But it also has infrastructure capable of supporting a variety of image formats and features of these formats.

Nuke is capable of driving progressive decoding, animated image rendering, progressive animated image rendering, drawing vector images directly or converting them to bitmaps, parsing thumbnails included in the image containers, and more.

- [Image Decoding Infrastructure](#image-decoding-infrastructure)
  * [ImageDecoding Protocol](#imagedecoding-protocol)
  * [Registering Decoders](#registering-decoders)
  * [Progressive Decoding](#progressive-decoding)
  * [Rendering Engines](#rendering-engines)
- [Built-In Image Decoders](#built-in-image-decoders)
  * [`ImageDecoders.Default`](#-imagedecodersdefault-)
  * [`ImageDecoders.Empty`](#-imagedecodersempty-)
- [Image Encoding Infrastructure](#image-encoding-infrastructure)
- [Built-In Image Encoders](#built-in-image-encoders)
  * [`ImageEncoders.Default`](#-imageencodersdefault-)
  * [`ImageEncoders.ImageIO`](#-imageencodersimageio-)
- [Supported Formats](#supported-formats)
  * [Basic Image Formats (JPEG, PNG, etc)](#basic-image-formats--jpeg--png--etc-)
  * [Progressive JPEG](#progressive-jpeg)
  * [HEIF](#heif)
  * [GIF](#gif)
  * [SVG](#svg)
  * [WebP](#webp)

## Image Decoding Infrastructure

### ImageDecoding Protocol

At the core of the decoding infrastructure is the `ImageDecoding` protocol.

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

`ImageContainer` is a struct which wraps the decoded image itself along with (optionally) the original data and some additional information. The decoder decides what to attach to the container.

```swift
public struct ImageContainer {
    // Either `UIImage` or `NSImage` depending on the platform.
    public let image: PlatformImage
    public let data: Data?
    public let userInfo: [AnyHashable: Any]
```

When the very first chunk of the image data is loaded, `ImagePipeline` creates a decoder for the given image format.

The pipeline uses `ImageDecoderRegistry` to find the decoder.  The decoder is created once and is reused across a single image decoding session until the final chunk of data is downloaded. If your decoder supports progressive decoding, make it a `class` if you need to keep some state within a single decoding session. You can also return a shared instance of the decoder if needed.

> Tip: `decode(_:)` method only passes `data` to the decoder. However, if you need any additional information in the decoder, you can pass it when instantiating a decoder. `ImageDecodingContext` provides everything that you might need.
>
> You can also take advantage of `ImageRequestOptions.userInfo` to pass any kind of information that you might want to the decoder. For example, you may pass the target image view size to the SVG decoder to let it know the size of the image to create.  

The decoding is performed in the background on the operation queue provided in `ImagePipeline.Configuration`. There is always only one decoding request at a time. The pipeline is not going to call `decodePariallyDownloadedData(_:)` until you are finished with the previous chunk.

### Registering Decoders

To register the decoders, use `ImageDecoderRegistry`. There are two ways to register the decoder.

The preferred approach is to make sure your decoders implements `ImageDecoderRegistering` protocol.

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

By default, the registry is initialzied with a single registered decoder, the default one:

```swift
public final class ImageDecoderRegistry {
    public init() {
        self.register(ImageDecoders.Default.self)
    }
}
```

If for some reason `ImageDecoderRegistering` does not work for you, use another `register(_:)` method version:

```swift
// Note: ImageDecoders.SVG not included in the framework.
ImageDecoderRegistry.shared.register { context: ImageDecodingContext in
    // Replace this with whatever works for. There are no magic numbers
    // for SVG like are used for other binary formats, it's just XML.
    let isSVG = context.urlResponse?.url?.absoluteString.hasSuffix(".svg") ?? false
    return isSVG ? ImageDecoders.SVG() : nil
}
```

> In order to determine image type, use `ImageType` initializer which takes data as input. `ImageType` represets uniform type identifiers, or UTI.

When you register a decoder, you have access to the entire decoding context for the given decoding session:

```swift
public struct ImageDecodingContext {
    public let request: ImageRequest
    public let data: Data
    public let urlResponse: URLResponse?
}
```

### Progressive Decoding

To enable progressive image decoding set `isProgressiveDecodingEnabled` configuration option of the image pipeline to `true`.

<img align="right" width="360" alt="Progressive JPEG" src="https://user-images.githubusercontent.com/1567433/59148764-3af73c00-8a0d-11e9-9d49-ded2d509380a.png">

```swift
let pipeline = ImagePipeline {
    $0.isProgressiveDecodingEnabled = true
    
    // If `true`, the pipeline will store all of the progressively generated previews
    // in the memory cache. All of the previews have `isPreview` flag set to `true`.
    $0.isStoringPreviewsInMemoryCache = true
}
```

And that's it, the pipeline will automatically do the right thing and deliver the progressive scans via the `progress` closure as they arrive:

```swift
let imageView = UIImageView()
let task = ImagePipeline.shared.loadImage(
    with: url,
    progress: { response, _, _ in
        if let response = response {
            imageView.image = response.image
        }
    },
    completion: { result in
        // Display the final image
    }
)
```

### Rendering Engines

The decoders in Nuke work at download time - decoders produce images as data arrives, progressive decoders might produce mutliple previews of the final image. There are, however, scenarios in which decoding at download time doesn't work. One of this scenarios is displaying animated images.

For animated images, it is not feasible to decode all of the animation frames and put them in memory as bitmaps at download time, it will just consume too much memory. What you typically want to do is postpone decoding to rendering time. When the animate image is displayed, a rendering engine, like [Gifu](https://github.com/kaishin/Gifu) or other, will decode and cache image frames as they are needed for display.

Rendering is not in the scope of Nuke. For static images, you can use platform `UIImageView` (or `NSImageView`, or `WKInterfaceImage` depending on your platform). For animated images, you need a rendering engine, like [Gifu](https://github.com/kaishin/Gifu). If you are using short MP4 clips instead of GIFs, that also works. You can use Nuke to download and cache data, and use `AVPlayer` to render it.

## Built-In Image Decoders

All decoders live in `ImageDecoders` namespace.

### `ImageDecoders.Default`

This is the decoder that is used by default if no other decoders are found. It uses native `UIImage(data:)` (and `NSImage(data:)`) initializers to create images from data.

> When working with `UIImage`, the decoder automatically sets the scale of the image to match the scale of the screen.

The default `ImageDecoders.Default` also supports progressively decoding JPEG. It produces a new preview every time it encounters a new full frame.

### `ImageDecoders.Empty`

This decoder returns an empty placeholder image and attaches image data to the image container. It could also be configured to return partially downloaded data.

Why is it useful? Let's say you want to render SVG using a third party framework directly in a view. Most likely, this framework is not going to use `UIImage` component, it works directly with `Data`. `ImageDecoders.Empty` allows you to pass this data to the rendering framework. 

## Image Encoding Infrastructure

To encode images, use types conforming to the following protocol:

```swift
public protocol ImageEncoding {
    func encode(image: PlatformImage) -> Data?
}
```

There is currently no dedicated `ImageEncoderRegistry`. To change which encoder the pipeline uses to encode downloaded images - in case data caching of final downloaded images is enabled - use the pipeline configuration.

## Built-In Image Encoders

All encooders live in `ImageEncoders` namespace.

### `ImageEncoders.Default`

Encodes opaque images as `jpeg` and images with opacity as `png`. Can be configured to use `heif` instead of `jpeg` using `ImageEncoders.Default.isHEIFPreferred` option.

### `ImageEncoders.ImageIO`

An [Image I/O](https://developer.apple.com/documentation/imageio) based encoder.

Image I/O is a system framework that allows applications to read and write most image file formats. This framework offers high efficiency, color management, and access to image metadata.

Usage:

```swift
let image: UIImage
let encoder = ImageEncoders.ImageIO(type: .heif, compressionRatio: 0.8)
let data = encoder.encode(image: image)
```

## Supported Formats

### Basic Image Formats (JPEG, PNG, etc)

Any [format natively supported](https://developer.apple.com/library/archive/documentation/2DDrawing/Conceptual/DrawingPrintingiOS/LoadingImages/LoadingImages.html#//apple_ref/doc/uid/TP40010156-CH17-SW7) by the platform, is also supported by Nuke. This includes:

- PNG
- TIFF
- JPEG
- GIF
- BMP
- ICO
- CUR
- XBM

You can use the basic `UIImageView`/`NSImageView`/`WKInterfaceImage` to render the images of any of the natively supported formats.

### Progressive JPEG

**Decoding**

The default image decoder `ImageDecoders.Default` supports progressive JPEG. The decoder will automatically detect when there are new scans available, and produce new images if needed.

> Please note, that to enable progressive decoding in the first place, you need to enable it on the pipeline level. For more information, see [Progressive Decoding](#progressive-decoding)

**Encoding**

None.

**Rendering**

To render the progressive JPEG, you can use the basic `UIImageView`/`NSImageView`/`WKInterfaceImage`. The default image view loading extensions also supports displaying progressive scans. 

<hr/>

### HEIF

**Decoding**

The default image decoder `ImageDecoders.Default` supports [HEIF](https://en.wikipedia.org/wiki/High_Efficiency_Image_File_Format)

**Encoding**

The default image encoder `ImageEncoders.Default` supports [HEIF](https://en.wikipedia.org/wiki/High_Efficiency_Image_File_Format), however it doesn't use it by default. To enable it, use `ImageEncoders.Default.isHEIFPreferred` option.

To encode images in HEIF directly, use `ImageEncoders.ImageIO`:

```swift
let image: UIImage
let encoder = ImageEncoders.ImageIO(type: .heif, compressionRatio: 0.8)
let data = encoder.encode(image: image)
```

One of the scenarios in which you may find this option useful is data caching. By default, the pipeline stores only the original image data. To store downloaded and processed images instead, set `dataCacheOptions.storedItems` to `[.finalImage]`. With HEIF encoding enabled, you can save a bit of disk space by transcoding downloaded images into HEIF.

**Rendering**

To render HEIF images, you can use the basic `UIImageView`/`NSImageView`/`WKInterfaceImage`.

<hr/>

### GIF

**Decoding**

The default image decoder `ImageDecoders.Default` automatically recognizes GIFs. It creates an image container (`ImageContainer`) with the first frame of the GIF as a placeholder and attaches the original image data to the container, so that you can perform just-in-time decoding at rendering time.

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

To see this code in action, check out the demo project attached in the repo.

> `GIF` is not the most efficient format for transferring and displaying animated images. The current best practice is to [use short videos instead of GIFs](https://developers.google.com/web/fundamentals/performance/optimizing-content-efficiency/replace-animated-gifs-with-video/) (e.g. `MP4`, `WebM`). There is a PoC available in the demo project which uses Nuke to load, cache and display an `MP4` video.

<hr/>

### SVG

**Decoding**

There is currently no support for decoding SVG images and rendering them into bitmap (`UIImage`/`NSImage`). What you can do instead is use `ImageDecoders.Empty` to pass the original image data to your SVG-enabled view and render is using an external mechanism.

**Encoding**

None.

**Rendering**

To render SVG, consider using [SwiftSVG](https://github.com/mchoe/SwiftSVG), [SVG](https://github.com/SVGKit/SVGKit), or other frameworks. Here is an example of `SwiftSVG` being used to render vector images.

```swift
ImageDecoderRegistry.shared.register { context in
    // Replace this with whatever works for you. There are no magic numbers
    // for SVG like are used for other binary formats, it's just XML.
    let isSVG = context.urlResponse?.url?.absoluteString.hasSuffix(".svg") ?? false
    return isSVG ? ImageDecoders.Empty() : nil
}

let url = URL(string: "https://upload.wikimedia.org/wikipedia/commons/9/9d/Swift_logo.svg")!
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

> Please keep in mind that most of these frameworks are limited in terms of supported SVG features.

<hr/>

### WebP

[WebP](https://developers.google.com/speed/webp) support is provided by [Nuke WebP Plugin](https://github.com/ryokosuge/Nuke-WebP-Plugin) built by [Ryo Kosuge](https://github.com/ryokosuge). Please follow the instructions from the repo.
