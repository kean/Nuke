# ``NukeUI``

Image loading for SwiftUI, UIKit, and AppKit views.

## Overview

There are four main views provided by the framework:

- ``LazyImage`` for SwiftUI
- ``LazyImageView`` for UIKit and AppKit

``LazyImage`` is designed similar to the native [`AsyncImage`](https://developer.apple.com/documentation/SwiftUI/AsyncImage), but it uses [Nuke](https://github.com/kean/Nuke) for loading images so you can take advantage of all of its features, such as caching, prefetching, task coalescing, smart background decompression, request priorities, and more.

![nukeui demo](nukeui-preview)

## Topics

### Essentials

- ``LazyImage``
- ``LazyImageView``
- ``LazyImageState``

### Helpers

- ``FetchImage``
