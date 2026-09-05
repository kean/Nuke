# ``NukeUI``

Image loading for SwiftUI, UIKit, and AppKit views.

## Overview

There are two main views provided by the framework:

- ``LazyImage`` for SwiftUI
- ``LazyImageView`` for UIKit and AppKit

The module also provides <doc:ImageViewExtensions> – a set of global functions that load images into existing `UIImageView` and `NSImageView` instances. They were a separate `NukeExtensions` module before Nuke 14.

Both views play animated images – GIF, APNG, animated WebP, and HEIC and AVIF sequences – with no setup. See <doc:AnimatedImages>.

``LazyImage`` is designed similar to the native [`AsyncImage`](https://developer.apple.com/documentation/SwiftUI/AsyncImage), but it loads images with `ImagePipeline`. You can take advantage of all of its features, such as caching, prefetching, task coalescing, smart background decompression, request priorities, and more.

![nukeui demo](nukeui-preview)

## Topics

### Essentials

- ``LazyImage``
- ``LazyImageView``

### Animated Images

- <doc:AnimatedImages>
- ``AnimatedImage``
- ``AnimatedImageView``
- ``AnimatedImagePlayer``

### Image View Extensions

- <doc:ImageViewExtensions>
- ``loadImage(with:options:into:completion:)-(URL?,_,_,_)``
- ``cancelRequest(for:)``
- ``ImageLoadingOptions``
- ``ImageDisplaying``
- ``ImageDisplayingView``

### Helpers

- ``LazyImageState``
- ``FetchImage``
