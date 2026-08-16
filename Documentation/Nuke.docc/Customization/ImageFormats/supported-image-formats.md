# Supported Formats

Learn which image formats Nuke decodes, encodes, and displays out of the box.

## Overview

Nuke doesn't implement image codecs. ``ImageDecoders/Default`` – the decoder the pipeline uses unless you register your own – hands the data to `UIImage(data:)`/`NSImage(data:)`, which goes through Image I/O. Anything the current OS can read, Nuke can read, and the list is long: JPEG, PNG, GIF, HEIF, WebP, AVIF, JPEG XL, TIFF, BMP, ICO, CUR, camera RAW, and more.

Recognizing a format is a separate concern from decoding it. ``AssetType`` sniffs the leading bytes of the data to name the format, and it deliberately knows about fewer formats than Image I/O decodes. When the sniffer doesn't recognize the data, ``ImageContainer/type`` is `nil` and the image still decodes normally – nothing in the pipeline gates on the type.

Nuke can also drive progressive decoding, animated image rendering, drawing vector images directly or converting them to bitmaps, parsing thumbnails included in the image containers, and more.

## Support Matrix

| Format | ``AssetType`` | Decode | Encode | Previews | Animation |
| --- | --- | --- | --- | --- | --- |
| JPEG | ``AssetType/jpeg`` | ✅ | ✅ | Automatic (progressive JPEG) | – |
| PNG | ``AssetType/png`` | ✅ | ✅ | Opt-in | First frame only |
| GIF | ``AssetType/gif`` | ✅ | ✅ | Automatic (single preview) | ✅ (data attached) |
| HEIC | ``AssetType/heic`` | ✅ | ✅ | Opt-in | First frame only |
| WebP | ``AssetType/webp`` | ✅ | ❌ | Opt-in | First frame only |
| AVIF | – | ✅ | ✅ recent OS only | Opt-in | First frame only |
| JPEG XL | ``AssetType/jxl`` | ✅ iOS 17, macOS 14 | ❌ | Opt-in | – |
| JPEG 2000 | ``AssetType/jpeg2000`` | ✅ | ✅ | Opt-in | – |
| TIFF | ``AssetType/tiff`` | ✅ | ✅ | Opt-in | – |
| BMP | ``AssetType/bmp`` | ✅ | ✅ | Opt-in | – |
| ICO | ``AssetType/ico`` | ✅ | ✅ | Opt-in | – |
| CUR | – | ✅ | ❌ | Opt-in | – |
| Camera RAW | ``AssetType/tiff`` or – | ✅ | ❌ | Opt-in (embedded thumbnail) | – |
| SVG | – | ❌ | ❌ | – | – |
| MP4, M4V, MOV | ``AssetType/mp4``, ``AssetType/m4v``, ``AssetType/mov`` | `NukeVideo` | ❌ | – | ✅ `NukeVideo` |

Reading the columns:

- **``AssetType``** – the type `AssetType(data)` returns for this format, or `–` if the sniffer doesn't recognize it. A `–` doesn't prevent decoding, it only means ``ImageContainer/type`` is `nil`.
- **Decode** – whether ``ImageDecoders/Default`` produces an image. Formats without a version note are decodable on every OS Nuke supports (iOS 16, tvOS 16, macOS 13, watchOS 9, visionOS 1).
- **Encode** – whether the format can be used with ``ImageEncoders/ImageIO``. ``ImageEncoders/Default`` only ever picks JPEG, PNG, or HEIC; the rest need an explicit encoder.
- **Previews** – behavior once ``ImagePipeline/Configuration-swift.struct/isProgressiveDecodingEnabled`` is on, which it isn't by default. "Automatic" means previews arrive with no further setup; "Opt-in" means you also have to select a policy via ``ImagePipeline/Delegate/previewPolicy(for:pipeline:)``, and whether Image I/O can produce anything from a partial file is format-dependent.
- **Animation** – "First frame only" means the built-in decoder produces a still image even when the file has multiple frames. See <doc:supported-image-formats#Animated-Images>.

> Tip: The matrix reflects what Apple's frameworks ship today. Both halves are queryable at runtime: `CGImageSourceCopyTypeIdentifiers()` for decoding, ``ImageEncoders/ImageIO/isSupported(type:)`` for encoding.

## Format Detection

``AssetType`` matches magic numbers at the start of the data:

```swift
AssetType(data) // .jpeg, .png, .gif, ...
AssetType.png.utType?.preferredMIMEType // "image/png"
```

The sniffer returns one of the types declared on ``AssetType`` and nothing else. A few consequences are worth knowing:

- **AVIF, HEIF (`mif1`), and CUR decode but sniff as `nil`.** ISO base media files are matched by their major brand, and the AVIF and bare-HEIF brands aren't in the table. CUR starts with `00 00 02 00`, one byte away from the ICO signature. The images load; ``ImageContainer/type`` is just empty.
- **A sniffed type describes the bytes, not the semantics.** Most camera RAW formats – DNG, CR2, NEF, ARW – are TIFF containers, so they sniff as ``AssetType/tiff``.
- **A `nil` type is not an error.** Only two places in the pipeline read the type: GIF detection in ``ImageDecoders/Default``, and `AssetType.isVideo` in `NukeVideo`.
- **Video types are recognized without `NukeVideo`.** ``AssetType/mp4``, ``AssetType/m4v``, and ``AssetType/mov`` are always sniffable, but only `ImageDecoders.Video` can decode them, and you have to register it yourself.

## Progressive JPEG

**Decoding**

``ImageDecoders/Default`` supports progressive JPEG via `CGImageSourceCreateIncremental`. When ``ImagePipeline/Configuration-swift.struct/isProgressiveDecodingEnabled`` is `true`, the pipeline produces previews as data arrives.

By default, progressive previews are only enabled for progressive JPEGs and GIFs (``ImagePipeline/PreviewPolicy``). Baseline JPEGs, PNGs, and other formats produce no previews unless explicitly configured via ``ImagePipeline/Delegate/previewPolicy(for:pipeline:)``.

For progressive JPEGs with large EXIF headers where `CGImageSourceCreateIncremental` fails to produce incremental previews, the decoder automatically falls back to generating a thumbnail from the available data.

**Encoding**

None. `CGImageDestination` writes baseline JPEG.

**Rendering**

To render progressive JPEG, you can use the basic `UIImageView`/`NSImageView`/`WKInterfaceImage`. The default image view loading extensions also support displaying progressive previews.

## HEIF

**Decoding**

``ImageDecoders/Default`` supports [HEIF](https://en.wikipedia.org/wiki/High_Efficiency_Image_File_Format).

Files with the `heic`, `heix`, `heim`, `heis`, `hevc`, `hevx`, `hevm`, and `hevs` brands sniff as ``AssetType/heic``. Generic HEIF files using the `mif1` brand decode too, but sniff as `nil`.

**Encoding**

``ImageEncoders/Default`` supports HEIF but doesn't use it by default. To enable it, use ``ImageEncoders/Default/isHEIFPreferred``.

You can use ``ImageEncoders/ImageIO`` directly:

```swift
let image: UIImage
let encoder = ImageEncoders.ImageIO(type: .heic, compressionRatio: 0.8)
let data = encoder.encode(image)
```

**Rendering**

To render HEIF images, you can use `UIImageView`/`NSImageView`/`WKInterfaceImage`.

## WebP

[WebP](https://developers.google.com/speed/webp) is decoded natively via Image I/O – no plugins required. Support landed in macOS 11, iOS 14, tvOS 14, and watchOS 7, so it's available on every OS version Nuke supports.

Image I/O has no WebP encoder. ``ImageEncoders/ImageIO/isSupported(type:)`` returns `false` for ``AssetType/webp`` on every current platform, and animated WebP decodes to its first frame.

## AVIF

[AVIF](https://en.wikipedia.org/wiki/AVIF) decodes natively on every OS Nuke supports.

``AssetType`` doesn't sniff AVIF: the format is an ISO base media container with an `avif` major brand, which isn't one of the recognized brands. Images decode normally, but ``ImageContainer/type`` is `nil`.

AVIF encoding arrived later than decoding and is only available on recent OS versions, so check before using it:

```swift
let avif: AssetType = "public.avif"
if ImageEncoders.ImageIO.isSupported(type: avif) {
    let data = ImageEncoders.ImageIO(type: avif).encode(image)
}
```

> Note: There is no ``AssetType`` constant for AVIF, and `UTType` doesn't declare one either, so the identifier has to be spelled out.

## JPEG XL

[JPEG XL](https://en.wikipedia.org/wiki/JPEG_XL) decodes natively on macOS 14, iOS 17, tvOS 17, and watchOS 10. Both the container signature and the naked codestream sniff as ``AssetType/jxl``. There is no encoder.

Because Nuke supports OS versions older than these, guard any JPEG XL-specific code:

```swift
if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
    // JPEG XL data decodes here
}
```

## JPEG 2000

[JPEG 2000](https://en.wikipedia.org/wiki/JPEG_2000) sniffs as ``AssetType/jpeg2000`` from either the JP2 signature box or a raw codestream.

Apple's documentation lists `public.jpeg-2000` as a macOS-only identifier, but current iOS releases report both read and write support. Treat it as a system-dependent format and check at runtime rather than relying on the platform.

## Camera RAW

Image I/O decodes RAW files from most camera vendors – Canon, Nikon, Sony, Fujifilm, Olympus, Panasonic, Pentax, Leica, Hasselblad, Adobe DNG, and others. Nuke passes them straight through, so they load without any extra setup.

``AssetType`` has no RAW constants – there are dozens of vendor-specific identifiers. Most RAW files are TIFF containers under the hood and sniff as ``AssetType/tiff``; the rest, such as Canon's ISO-base-media CR3, sniff as `nil`.

RAW files are large and slow to decode at full size. Use ``ImageRequest/thumbnail`` to have Image I/O read the embedded preview instead of the full sensor data:

```swift
var request = ImageRequest(url: url)
request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 512)
let image = try await ImagePipeline.shared.image(for: request)
```

## GIF

**Decoding**

``ImageDecoders/Default`` automatically recognizes GIFs. It creates an image container (``ImageContainer``) with the first frame of the GIF as a placeholder and attaches the original image data to the container so that you can perform just-in-time decoding at rendering time.

**Encoding**

Image I/O can write GIF, but ``ImageEncoders/ImageIO`` writes a single frame – it has no way to express an animation.

**Rendering**

To render animated GIFs, please consider using one of the open-source GIF rendering engines, like [Gifu](https://github.com/kaishin/Gifu), [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage), or other.

**Gifu Example**

```swift
/// A custom image view that supports downloading and displaying animated images.
final class ImageView: UIView {
    private let imageView: GIFImageView
    private let spinner: UIActivityIndicatorView
    private var task: Task<Void, Never>?

    /* Initializers skipped */

    func setImage(with url: URL) {
        prepareForReuse()

        if let container = ImagePipeline.shared.cache[url] {
            display(container)
            if !container.isPreview {
                return
            }
        }

        spinner.startAnimating()
        task = Task { [weak self] in
            defer { self?.spinner.stopAnimating() }
            guard let response = try? await ImagePipeline.shared.imageTask(with: url).response else {
                return
            }
            self?.display(response.container)
        }
    }

    private func display(_ container: ImageContainer) {
        if let data = container.data {
            imageView.animate(withGIFData: data)
        } else {
            imageView.image = container.image
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

## Animated Images

GIF is the only format the built-in decoder treats as animated. ``ImageDecoders/Default`` attaches ``ImageContainer/data`` for GIFs and nothing else, so animated WebP, animated AVIF, HEICS, and APNG all decode to a single still frame.

To animate one of those formats, register a decoder that attaches the data, then hand it to a rendering engine that understands the format:

```swift
ImageDecoderRegistry.shared.register { context in
    AssetType(context.data) == .webp ? ImageDecoders.Empty(assetType: .webp) : nil
}
```

``ImageDecoders/Empty`` puts a blank placeholder in ``ImageContainer/image`` and the original bytes in ``ImageContainer/data``, leaving the rendering engine to do the decoding. It's the same pattern to use for any format Image I/O can't read at all. Learn more in <doc:image-decoding>.

## SVG

**Decoding**

There is currently no built-in support for SVG. Use ``ImageDecoders/Empty`` to pass the original image data to an SVG-enabled view and render it using an external mechanism.

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

let url = URL(string: "https://upload.wikimedia.org/wikipedia/commons/9/9d/Swift_logo.svg")!
let response = try await ImagePipeline.shared.imageTask(with: url).response
guard let data = response.container.data else {
    return
}
// You can render an image using whatever size you want, vector!
let targetBounds = CGRect(origin: .zero, size: CGSize(width: 300, height: 300))
let svgView = UIView(SVGData: data) { layer in
    layer.fillColor = UIColor.orange.cgColor
    layer.resizeToFit(targetBounds)
}
view.addSubview(svgView)
svgView.bounds = targetBounds
svgView.center = view.center
```

> Important: Both [SwiftSVG](https://github.com/mchoe/SwiftSVG) and [SVG](https://github.com/SVGKit/SVGKit) only support a subset of SVG features.

## Video

``AssetType`` recognizes MP4, M4V, and QuickTime containers, but the `Nuke` module can't decode them. Add the `NukeVideo` product and register its decoder:

```swift
ImageDecoderRegistry.shared.register(ImageDecoders.Video.init)
```

`ImageDecoders.Video` generates a still preview and attaches the downloaded data to the container, which `VideoPlayerView` then plays.
