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
ImageTask #41 · success · 496.0 ms · from network
kind:        image
url:         https://cdn.example.com/photos/1024.jpg
processors:  com.github.kean/nuke/resize?s=(300.0, 300.0),cm=.aspectFill,crop=false,upscale=false
priority:    normal
image:       300×300 · jpeg
download:    1.2 MB
coalesced:   no
pipeline:    3B0C6E4A-6D5C-4F0E-9E43-2C7D1A9B5F10

started                  0.3 ms   at 14:22:42.325
u5 loadImage [resize]
├─ memoryLookup          0.0 ms   miss
├─ diskLookup            0.6 ms   miss
├─ u6 loadImage
│  ├─ memoryLookup       0.0 ms   miss
│  ├─ diskLookup         0.2 ms   miss
│  └─ u7 fetchOriginalImage
│     ├─ u8 fetchOriginalData
│     │  ├─ download   412.6 ms   █████████████████  network · 1.2 MB · HTTP 200 · first byte 92.9 ms
│     │  └─ diskStore    0.1 ms   1.2 MB
│     └─ decode         38.4 ms   ██  ImageDecoders.Default · jpeg 4032×3024
├─ process              26.1 ms   jpeg 300×300
…
finished               496.0 ms   at 14:22:42.821
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
