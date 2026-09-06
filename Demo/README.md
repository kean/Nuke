# Nuke Demo

A demo app that covers the main ways to use Nuke. It is a target in the main
Xcode project, so it always builds against the sources in this repo.

```bash
open Nuke.xcodeproj
```

Select the **NukeDemo** scheme and run it (iOS 17+). No dependencies, no setup:
the images are loaded over the network from public URLs.

## Screens

The sections mirror the [documentation](https://kean-docs.github.io/nuke/documentation/nuke).
Every screen has a question mark in the navigation bar that explains what it
shows, with the API it is about and the details worth knowing.

### Essentials

| Screen | Shows |
|--|--|
| **Image Pipeline** | `ImagePipeline.imageTask(with:)`, the event stream, progress, cancellation, and where the response came from |
| **LazyImage** | The SwiftUI view: loading states, transitions, processors, priority, and completion |
| **UIImageView** | `loadImage(with:options:into:)` in a collection view: cell reuse, placeholders, failure images, transitions |
| **LazyImageView** | The UIKit view with its placeholder and failure views |

### Customization

| Screen | Shows |
|--|--|
| **Image Processing** | The built-in processors and two ways to write your own |
| **Image Formats** | JPEG, PNG, WebP, animated GIF, and MP4 via `ImageDecoders.Video` |
| **Animated Images** | GIF, APNG, WebP, and HEIC playback with live diagnostics – the frame buffer, decode times, and dropped frames – in an inspector: beside the animation on iPad, in a sheet below it on iPhone |
| **Animation Memory** | A wall of animations sharing one memory budget, and what happens when they don't all fit |
| **Progressive JPEG** | Progressive decoding, with a throttled data loader that makes the scans visible |
| **Pipeline Delegate** | `willLoadData(for:urlRequest:pipeline:)` and a live log of the pipeline events |

### Performance

| Screen | Shows |
|--|--|
| **Prefetching** | `ImagePrefetcher` driven by `UICollectionViewDataSourcePrefetching` and by a SwiftUI grid |
| **Caching** | The memory cache, `URLCache`, and `DataCache` side by side, with the source of every image |
| **Stress Test** | The pipeline under fast scrolling with every cache disabled |

## Diagnostics

Launch the app with the `NUKE_DIAGNOSTICS` environment variable set – it is in
the scheme, unticked, under Run › Arguments › Environment Variables – and every
image task logs where its time went to Console, under the
`com.github.kean.NukeDemo` subsystem:

```
ImageTask #41 · image · normal · 496.0 ms · success · source: network
https://cdn.example.com/photos/1024.jpg · [Resize(300×300)]
coalesced: no

  +0.3      started
  +0.3      u5 · loadImage [Resize(300×300)]
  +0.3        memoryLookup  miss
  +0.3        diskLookup    miss · 0.6 ms
  …
  +496.0    finished
```

From the terminal, with the simulator booted:

```bash
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.github.kean.NukeDemo"'
```

## Structure

```
Demo
├── App              The app and the menu
├── Essentials       ImagePipeline, LazyImage, and the image views
├── Customization    Processing, formats, progressive decoding, delegate
├── Performance      Prefetching, caching, and the stress test
└── Helpers          Shared views, demo URLs, and a few small utilities
```
