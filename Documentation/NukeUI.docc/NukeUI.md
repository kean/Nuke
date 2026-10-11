# ``NukeUI``

Image loading for SwiftUI, UIKit, and AppKit views.

## Overview

There are two main views provided by the framework:

- ``LazyImage`` for SwiftUI
- ``LazyImageView`` for UIKit and AppKit

To load images into the image views you already have, use ``ImageLoader``. It loads an image into a `UIImageView` or an `NSImageView` with a single call, and into any other object that draws its state. It replaces the soft-deprecated `NukeExtensions`.

Both views play animated images – GIF, APNG, animated WebP, and HEIC and AVIF sequences – with no setup. See <doc:AnimatedImages>.

``LazyImage`` is designed similar to the native [`AsyncImage`](https://developer.apple.com/documentation/SwiftUI/AsyncImage), but it loads images with `ImagePipeline`. You can take advantage of all of its features, such as caching, prefetching, task coalescing, smart background decompression, request priorities, and more.

![nukeui demo](nukeui-preview)

## Topics

### Essentials

- ``LazyImage``
- ``LazyImageView``
- ``ImageLoader``

### Animated Images

- <doc:AnimatedImages>
- ``AnimatedImage``
- ``AnimatedImageView``
- ``AnimatedImagePlayer``

### Helpers

- ``LazyImageState``
- ``FetchImage``
- ``ImageLoaderDelegate``
