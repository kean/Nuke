# ``NukeUI``

Image loading for SwiftUI, UIKit, and AppKit views.

## Overview

There are four main views provided by the framework:

- ``LazyImage`` and ``Image`` for SwiftUI
- ``LazyImageView`` and ``ImageView`` for UIKit and AppKit

``LazyImage`` is designed similar to the native [`AsyncImage`](https://developer.apple.com/documentation/SwiftUI/AsyncImage), but it uses [Nuke](https://github.com/kean/Nuke) for loading images so you can take advantage of all of its features, such as caching, prefetching, task coalescing, smart background decompression, request priorities, and more.

![nukeui demo](nukeui-preview)

NukeUI supports progressive images, has GIF support powered by [Gifu](https://github.com/kaishin/Gifu), and can even play short videos, which is [a more efficient](https://web.dev/replace-gifs-with-videos/) way to display animated images.

## Topics

### Essentials

- ``LazyImage``
- ``LazyImageView``
- ``LazyImageState``

### Other Views

- ``Image``
- ``ImageView``
- ``AnimatedImageView``
- ``VideoPlayerView``

### Helpers

- ``FetchImage``
- ``ImageResizingMode``
