# Coming From Another Library

Find the Nuke API for what you use in Kingfisher, SDWebImage, or AsyncImage.

## Overview

``ImagePipeline`` in `Nuke` does the work of Kingfisher's `KingfisherManager` and SDWebImage's `SDWebImageManager`. The views are in `NukeUI`: `LazyImage` for SwiftUI, `ImageLoader` and `LazyImageView` for UIKit and AppKit, and `AnimatedImageView` wherever a platform image view goes.

> Important: The disk cache behaves differently. Kingfisher and SDWebImage store every image on disk and ignore the `Cache-Control` of the response. By default, Nuke stores images in `URLCache`, which follows those headers, so a CDN with weak headers makes an app download its images again. To get what you had, use ``ImagePipeline/Configuration-swift.struct/withDataCache(name:sizeLimit:)``:
>
> ```swift
> ImagePipeline.shared = ImagePipeline(configuration: .withDataCache())
> ```

## Kingfisher

| Kingfisher | Nuke |
|---|---|
| `KFImage(url)` | `LazyImage(url: url)` |
| `.placeholder { }`, `.onFailureImage(_:)` | `LazyImage(url: url) { state in }`, which draws each state |
| `.fade(duration:)` in SwiftUI | `LazyImage(url: url, transaction:)` |
| `.fade(duration:)` in UIKit | `ImageLoader.Presentation(transition: .fadeIn(duration:))` |
| `.onSuccess(_:)`, `.onFailure(_:)` | `.onCompletion(_:)` |
| `.cancelOnDisappear(true)` | `.onDisappear(.cancel)` |
| `imageView.kf.setImage(with: url)` | `ImageLoader.load(url, into: imageView)` |
| `KingfisherManager.shared.retrieveImage(with:)` | `ImagePipeline.shared.image(for: url)` |
| `AnimatedImageView` | `AnimatedImageView`, or `LazyImage(url:)`, which plays with no setup |
| `ImagePrefetcher(urls:).start()` | `ImagePrefetcher().startPrefetching(with:)` |
| `ImageCache.default` | `ImagePipeline.shared.cache` |
| `ImageDownloader` | `DataLoader`, and `DataLoading` to replace it |
| `.requestModifier(_:)` | `willLoadData(for:urlRequest:pipeline:)` |
| `DownsamplingImageProcessor(size:)` | `ImageRequest.ThumbnailOptions` |
| `RoundCornerImageProcessor(cornerRadius:)` | `.roundedCorners(radius:)` |
| `BlurImageProcessor(blurRadius:)` | `.gaussianBlur(radius:)` |
| `.forceRefresh` | `.reloadIgnoringCachedData` |
| `.onlyFromCache` | `.returnCacheDataDontLoad` |
| `.progressiveJPEG(_:)` | `isProgressiveDecodingEnabled` |
| `.retry(_:)` | `ImagePipeline.Configuration.retryPolicy` in <doc:retrying-requests> |
| `.alternativeSources(_:)` | `FallbackDelegate` in <doc:recipes> |
| `.lowDataModeSource(_:)` | `allowsConstrainedNetworkAccess` and `dataLoadingError` in <doc:recipes> |
| `.memoryCacheExpiration(_:)` | `ImageCache.ttl` and `imageCache(for:pipeline:)` in <doc:recipes> |
| `.diskCacheExpiration(_:)` | `Cache-Control`, or `dataCache(for:pipeline:)` in <doc:recipes> |

## SDWebImage

| SDWebImage | Nuke |
|---|---|
| `WebImage(url:)` | `LazyImage(url: url)` |
| `AnimatedImage(url:)` | `LazyImage(url: url)`, which plays with no setup |
| `.onSuccess(perform:)`, `.onFailure(perform:)` | `.onCompletion(_:)` |
| `imageView.sd_setImage(with: url)` | `ImageLoader.load(url, into: imageView)` |
| `sd_cancelCurrentImageLoad()` | `ImageLoader.loader(for: imageView).cancel()` |
| `SDAnimatedImageView` | `AnimatedImageView` |
| `SDWebImageManager.shared.loadImage(with:options:progress:completed:)` | `ImagePipeline.shared.image(for: url)` |
| `SDWebImagePrefetcher.shared.prefetchURLs(_:)` | `ImagePrefetcher().startPrefetching(with:)` |
| `SDImageCache.shared` | `ImagePipeline.shared.cache` |
| `maxMemoryCost` | `ImageCache.costLimit` |
| `maxDiskSize` | `DataCache.sizeLimit` |
| `SDWebImageDownloaderRequestModifier` | `willLoadData(for:urlRequest:pipeline:)` |
| `SDImageCodersManager.shared.addCoder(_:)` | `ImageDecoderRegistry.shared.register(_:)` |
| `SDImageResizingTransformer` | `.resize(size:)` |
| `SDImageRoundCornerTransformer` | `.roundedCorners(radius:)` |
| `SDImageBlurTransformer` | `.gaussianBlur(radius:)` |
| `SDWebImageProgressiveLoad` | `isProgressiveDecodingEnabled` |
| `SDWebImageFromCacheOnly` | `.returnCacheDataDontLoad` |
| `SDWebImageRetryFailed` | Nothing to set: Nuke has no list of failed URLs |
| `SDImageCoderDecodeScaleDownLimitBytes` | `ImageRequest.ThumbnailOptions`, and `limitMemory(to:)` in <doc:recipes> |
| `SDImageCoderDecodeToHDR` | `HDRDecoder` in <doc:recipes> |

## AsyncImage

`LazyImage` passes the state to the closure, not a phase:

```swift
// AsyncImage
AsyncImage(url: url) { phase in
    switch phase {
    case .success(let image): image.resizable()
    case .failure: Color.red
    default: ProgressView()
    }
}

// Nuke
LazyImage(url: url) { state in
    if let image = state.image {
        image.resizable()
    } else if state.error != nil {
        Color.red
    } else {
        ProgressView()
    }
}
```

| AsyncImage | Nuke |
|---|---|
| `AsyncImage(url:)` | `LazyImage(url: url)` |
| `AsyncImage(url:scale:content:placeholder:)` | `LazyImage(url: url) { state in }` |
| `AsyncImage(url:scale:)` | `ImageRequest.scale` |
| `AsyncImage(url:scale:transaction:content:)` | `LazyImage(url: url, transaction:)` |
| `AsyncImage(request:)` | `LazyImage(request: ImageRequest(urlRequest:))` |
| `.asyncImageURLSession(_:)` | `.pipeline(_:)` on each view, or `ImagePipeline.shared` |
| `AsyncImagePhase.success` | `state.image` |
| `AsyncImagePhase.failure` | `state.error` |

## What Has No Counterpart

Some of what you used doesn't have an API in Nuke:

- **Kingfisher:** the `.placeholder` and `.fade` modifiers, helpers for `UIButton` and `NSTextAttachment` (`ImageLoader.load(_:into:render:)` covers any object), built-in indicators, Live Photo, and processors for cropping, tinting, and blending, which you write as an ``ImageProcessing``.
- **SDWebImage:** a list of failed URLs, reverse and bounce playback, encoding animations, the Objective-C API, and deployment below iOS 16.
- **AsyncImage:** setting the session in the environment. ``ImagePipeline/shared`` is the closest thing.
