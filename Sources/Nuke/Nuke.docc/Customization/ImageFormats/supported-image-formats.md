# Supported Image Formats

Nuke has built-in support for basic image formats like `jpeg`, `png`, and `heif`. It also has the infrastructure for supporting a variety of custom image formats.

Nuke is capable of driving progressive decoding, animated image rendering, progressive animated image rendering, drawing vector images directly or converting them to bitmaps, parsing thumbnails included in the image containers, and more.

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
