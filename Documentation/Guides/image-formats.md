# Supported Image Formats

Nuke offers built-in support for basic image formats like `jpeg`, `png`, and `heif`. But it also has infrastructure capable of supporting a variety of image formats and features of these formats, including but not limited to: 

- [`heif`](#heif)
- [`gif`](#gif)
- [`svg`](#svg)
- [`webp`](#webp)

Nuke is capable of driving progressive decoding, animated image rendering, progressive animated image rendering, drawing vector images directly or converting them to bitmaps, parsing thumbnails included in the image containers, and more.

## Image Decoding Infrastructure

At the core of the decoding infrastructure is `ImageDecoding` protocol.

> In Nuke 8.5 this protocol was named `_ImageDecoding`.

```swift
public protocol ImageDecoding {
    /// Produces an image from the given image data.
    func decode(data: Data) -> ImageContainer?

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

When the very first chuck of the image data is loaded, `ImagePipeline` finds a decoder for the given image format.

The pipeline uses `ImageDecoderRegistry` to find the decoder. Use the shared registry to add custom decoders.

```swift
// Note: ImageDecoders.SVG not included in the framework.
ImageDecoderRegistry.shared.register { context: ImageDecodingContext in
    // Replace this with whatever works for. There are no magic numbers
    // for SVG like are used for other binary formats, it's just XML.
    let isSVG = context.urlResponse?.url?.absoluteString.hasSuffix(".svg") ?? false
    return isSVG ? ImageDecoders.SVG() : nil
}
```

When you register a decoder, you have access to the entire decoding context for the given decoding session:

```swift
public struct ImageDecodingContext {
    public let request: ImageRequest
    public let data: Data
    public let urlResponse: URLResponse?
}
```

The decoder is created once and is reused across a single image decoding session until the final chuck of data is downloaded. If your decoder supports progressive decoding, make it a `class` if you need to keep some state within a single decoding session. You can also return a shared instance of the decoder if needed.

> Tip: `decode(data:)` method only passes `data` to the decoder. However, if you need any additional information in the decoder, you can pass it when instantiating a decoder. `ImageDecodingContext` provides everything that you might need.
>
> You can also take advantage of `ImageRequestOptions.userInfo` to pass any kind of information that you might want to the decoder. For example, you may pass the target image view size to the SVG decoder to let it know the size of the image to create.  

The decoding is performed in the background on the operation queue provided in `ImagePipeline.Configuration`. There is always only one decoding request at a time. The pipeline is not going to call `decodePariallyDownloadedData(_:)` until you are finished with the previous chuck.

## Built-In Image Decoders

### `ImageDecoders.Default`

This is the decoder that is used by default if none other decoders are found. It uses native `UIImage(data:)` (and `NSImage(data:)`) initializers to create images from data.

> When working with `UIImage`, the decoder automatically sets the scale of the image to match the scale of the screen.

TBD: progressive decoding

### `ImageDecoders.Empty`

This decoders returns an empty placeholder image and attaches image data to the image container. It could also be configured to return partially downloaded data.

Why is it useful? Let's say you want to render SVG using a third party framework directly in a view. Most likely, this framework is not going to use `UIImage` component, it works directly with `Data`. `ImageDecoders.Empty` allows you to pass this data to the rendering framework. 

## Image Encoding Infrastructure

TBD:

## Supported Formats

### HEIF

**Decoding**

The default image decoder `ImageDecoders.Default` supports [HEIF](https://en.wikipedia.org/wiki/High_Efficiency_Image_File_Format)

**Encoding**

The default image encoder `ImageEncoders.Default` supports [HEIF](https://en.wikipedia.org/wiki/High_Efficiency_Image_File_Format), however it doesn't use it by default. To enable it, use a new experimental `ImageEncoder._isHEIFPreferred` option.

To encode images in HEIF directly, use `ImageEncoders.ImageIO`:

```swift
let image: UIImage
let encoder = ImageEncoders.ImageIO(type: .heif, compressionRatio: 0.8)
let data = encoder.encode(image: image)
```
One of the scenarios in which you may find this option useful is data caching. By default, the pipeline stores only the original image data. To store downloaded and processed images instead, set `dataCacheOptions.storedItems` to `[.finalImage]`. With HEIF encoding enabled, you can save a bit of disk space by transcoding downloaded images into HEIF.

**Rendering**

To render HEIF images, you can use the basic `UIImageView`/`NSImageView`/`WKInterfaceImage`.

### GIF

**Decoding**

The default image decoder `ImageDecoders.Default` automatically recognized GIFs. It creates an image container (`ImageContainer`) with the first frame of the GIF as placeholder and attaches the original image data to the container.

**Rendering**

To render animated GIFs, please consider using one of the open-souce GIF rendering engines, like [Gifu](https://github.com/kaishin/Gifu), [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage), or other.

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

### SVG

**Decoding**

There is currently no support for decoding SVG images and rendering them into bitmap (`UIImage`/`NSImage`). What you can do instead is use `ImageDecoders.Empty` to pass the original image data to your SVG-enabled view and render is using an external mechanism.

**Rendering**

To render SVG, consider using [SwiftSVG](https://github.com/mchoe/SwiftSVG), [SVG](https://github.com/SVGKit/SVGKit), or other frameworks. Here is an example of `SwiftSVG` being used to render vector images.

```swift
ImageDecoderRegistry.shared.register { context in
    // Replace this with whatever works for. There are no magic numbers
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

### WebP

**Decoding**

[WebP](https://developers.google.com/speed/webp) support is provided by [Nuke WebP Plugin](https://github.com/ryokosuge/Nuke-WebP-Plugin) built by [Ryo Kosuge](https://github.com/ryokosuge). Please follow the instructions from the repo.
