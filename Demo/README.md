# Nuke Demo

A demo app that covers the main ways to use Nuke. It is a target in the main
Xcode project, so it always builds against the sources in this repo.

```bash
open Nuke.xcodeproj
```

Select the **NukeDemo** scheme and run it (iOS 17+). No dependencies, no setup:
the images are loaded over the network from public URLs.

## Screens

The catalog follows the order an app tends to need things in rather than the
outline of the [documentation](https://kean-docs.github.io/nuke/documentation/nuke),
and ends with a single row into the [Lab](#lab). Every screen has a question
mark in the navigation bar that explains what it shows, with the API it is about
and the details worth knowing.

### Essentials

| Screen | Shows |
|--|--|
| **Image Pipeline** | `ImagePipeline.imageTask(with:)`, the event stream, progress, cancellation, and where the response came from |
| **LazyImage** | The SwiftUI view: loading states, transitions, processors, priority, and completion |
| **UIImageView** | `loadImage(with:options:into:)` in a collection view: cell reuse, placeholders, failure images, transitions |
| **LazyImageView** | The UIKit view with its placeholder and failure views |

### Processing & Formats

| Screen | Shows |
|--|--|
| **Image Processing** | The built-in processors and two ways to write your own |
| **Image Formats** | JPEG, PNG, WebP, animated GIF, and MP4 via `ImageDecoders.Video` |
| **Progressive Decoding** | The scans of a progressive JPEG, with a throttled data loader that makes them visible |

### Caching & Performance

| Screen | Shows |
|--|--|
| **Caching** | The memory cache, `URLCache`, and `DataCache` side by side, with the source of every image |
| **Prefetching** | `ImagePrefetcher` driven by `UICollectionViewDataSourcePrefetching` and by a SwiftUI grid |

### Animated Images

| Screen | Shows |
|--|--|
| **Animated Images** | GIF, APNG, WebP, and HEIC playback with live diagnostics – the frame buffer, decode times, and dropped frames – in an inspector: beside the animation on iPad, in a sheet below it on iPhone |

### Integration

| Screen | Shows |
|--|--|
| **Pipeline Delegate** | `willLoadData(for:urlRequest:pipeline:)` and a live log of the pipeline events |

## Lab

Instruments and torture rigs for whoever works on Nuke, behind the last row of
the catalog. Caches are disabled on purpose and budgets pushed past sensible
values, and the screens report numbers rather than explain an API – the catalog
screen for that API does the explaining.

| Screen | Group | Shows |
|--|--|--|
| **Scroll Stress** | Stress | The pipeline under fast scrolling with every cache disabled |
| **Animation Memory** | Animation | A wall of animations sharing one memory budget, and what happens when they don't all fit |

## Diagnostics

Launch the app with the `NUKE_DIAGNOSTICS_ENABLED` environment variable set – it is in
the scheme, unticked, under Run › Arguments › Environment Variables – and every
image task logs where its time went to Console, under the
`com.github.kean.NukeDemo` subsystem.

From the terminal, with the simulator booted:

```bash
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.github.kean.NukeDemo"'
```

For what a record contains and how to read the timeline, see
[Measure](../Documentation/Nuke.docc/Performance/performance-guide.md#measure) in the
Performance Guide.

## Structure

```
Demo
├── App              The app, the catalog and Lab menus, and the screen registry
├── Essentials       ImagePipeline, LazyImage, and the image views
├── Processing       Processors, image formats, and progressive decoding
├── Caching          Caching and prefetching
├── AnimatedImages   Animated image playback and its diagnostics
├── Integration      The pipeline delegate
├── Lab              Stress rigs and instruments for working on Nuke
├── Helpers          Shared views, demo URLs, and a few small utilities
└── Resources        The app icon, the logo, and a bundled animation
```
