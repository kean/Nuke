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

Launch the app with the `NUKE_DIAGNOSTICS_ENABLED` environment variable set – it is in
the scheme, unticked, under Run › Arguments › Environment Variables – and every
image task logs where its time went to Console, under the
`com.github.kean.NukeDemo` subsystem:

```
ImageTask #1 · success · 378.7 ms · from network
kind:        image
url:         https://cdn.example.com/photos/1024.jpg
processors:  com.github.kean/nuke/resize?s=(300.0, 300.0),cm=.aspectFill,crop=false,upscale=false
priority:    normal
image:       450×300 · jpeg
download:    317 KB
coalesced:   no
pipeline:    BC55A0B6-A39E-4108-8791-36D323B00F49

started                  1.1 ms   at 16:11:28.736
u1 loadImage [resize]
├─ memoryLookup          0.0 ms   miss
├─ diskLookup            0.3 ms   miss
├─ u2 loadImage
│  ├─ memoryLookup       0.0 ms   miss
│  ├─ diskLookup         0.0 ms   miss
│  └─ u3 fetchOriginalImage
│     ├─ u4 fetchOriginalData
│     │  ├─ download   340.1 ms   ██████████████████  network · 317 KB · HTTP 200 · first byte 292.2 ms
│     │  └─ diskStore    0.1 ms   317 KB
│     └─ decode         17.6 ms   ImageDecoders.Default · jpeg 1440×960 · work 13.2 ms
├─ process              14.1 ms   jpeg 450×300 · work 12.5 ms
└─ memoryStore           0.0 ms
finished               378.7 ms   at 16:11:29.114

URLSessionTask #1 · 339.7 ms
started                1.5 ms   at 16:11:28.739
networkLoad · https://cdn.example.com/photos/1024.jpg · HTTP 200 · h2 · TLS 1.3 · 151.101.1.1 · sent 178 bytes · received 318 KB
├─ blocked             3.3 ms
├─ domainLookup        1.0 ms
├─ connect            32.0 ms   ██
├─ secureConnection   24.0 ms
├─ request             0.1 ms
├─ waiting           229.4 ms   ░░░░░░░░░░░░░░
└─ response           47.6 ms   ███
finished             339.7 ms   at 16:11:29.077
```

The tree is the work the task waited on, with the time the task spent on every
row and a bar where a row took a large share of it. The second block is the
same download as `URLSession` measured it, on the clock of the session task.

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
