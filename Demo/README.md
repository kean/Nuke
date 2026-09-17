# Nuke Demo

A demo app that covers the main ways to use Nuke. It is a target in the main
Xcode project, so it always builds against the sources in this repo.

```bash
open Nuke.xcodeproj
```

Select the **NukeDemo** scheme and run it (iOS 17+). No dependencies, no setup:
the images are loaded over the network from public URLs, or offline from
[fixtures](#fixtures) the app makes itself.

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
| **UIKit Views** | `loadImage(with:options:into:)` next to `LazyImageView` in a collection view, on a picker: with the extension you own the placeholder, the failure image, and the transition; `LazyImageView` owns them. Cell reuse either way |

### Requests

| Screen | Shows |
|--|--|
| **Request Options** | One image and a panel of every `ImageRequest.Options` flag, the priority, and a thumbnail next to a resize processor. Each change runs the request again and shows where the image came from, what it cost in time, bytes, and memory, and the stages the task went through, read from its `ImageTask.Metrics` |

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
| **Pipeline Delegate** | A delegate that adds a header in `willLoadData`, leaves a URL token out of `cacheKey`, and keeps a private photo off the disk in `willCache`, with a live log of what the pipeline asks it |

## Lab

Instruments and torture rigs for whoever works on Nuke, behind the last row of
the catalog. Caches are disabled on purpose and budgets pushed past sensible
values, and the screens report numbers rather than explain an API – the catalog
screen for that API does the explaining.

| Screen | Group | Shows |
|--|--|--|
| **Pipeline HUD** | Instruments | Every figure behind the HUD – tasks, coalescing, cache hits, queues, decode times, bytes, caches, footprint, and frames – for each pipeline and all of them, with the switch and a reset |
| **Scroll Stress** | Stress | The pipeline under fast scrolling with every cache disabled, on fixtures or over the network |
| **Animation Memory** | Animation | A wall of animations sharing one memory budget, and what happens when they don't all fit |
| **Fixture Mode** | Rig | The switch that takes the whole demo offline, and every fixture with its size, the time it took to make, and a digest |
| **Automation** | Rig | Every launch argument and screen id, each with a `simctl launch` line to copy |

## Launch arguments

A few launch arguments open the app in a known state, so a script can take a
screenshot of any screen without tapping its way there. Pass them after the
bundle id, or add them under Edit Scheme › Run › Arguments Passed On Launch:

```bash
xcrun simctl launch booted com.github.kean.NukeDemo -demoScreen caching -demoLab 0
```

| Argument | Does |
|--|--|
| `-demoScreen <id>` | Opens the app on a screen, with the menus it is reached through beneath it. `lab` is the Lab menu; an id that no screen has opens the catalog and logs why |
| `-demoLab 0` | Leaves the Lab row out of the catalog, for a screenshot of the catalog alone |
| `-demoHUD 1` | Opens the app with the pipeline HUD on, folded into its pill; `expanded` opens its panel |
| `-demoFixtures offline` | Serves every image from [fixtures](#fixtures), with no network request; `network`, the default, loads the catalog over the network |
| `-demoDeterministic 1` | Starts the app the same way every time: offline, with the disk caches emptied, no fade on UIKit image views, and no random tokens |

The **Automation** screen in the Lab lists every id. An id stays the same when a
title changes.

## Fixtures

Offline, the demo loads no image from the network. Every URL it hands out is a
fixture's, `demo-fixture://nuke/<name>`: a stand-in for each photo with its
index drawn on it, a baseline and a progressive JPEG, a 12 MP JPEG, a PNG, two
GIFs (the long one has 200 frames), and an APNG, all drawn and encoded the
first time a load asks for them, plus a WebP, an animated WebP, and a video
bundled in `Resources/Fixtures`. The generated ones are the same bytes on every
run, so a run on fixtures can be compared with the last one.

Every pipeline's delegate sends a request for a fixture, and every request
while offline, to the fixture loader, which also answers the demo's network
URLs with their stand-ins; any other URL fails and says so in Console, under
the `Fixtures` category. Launch with `-demoFixtures offline`, or flip the switch
in **Fixture Mode** in the Lab, which applies to the screens opened next. Lab
screens that load photos start on fixtures either way.

The photo stream's URLs are in `Resources/photos.json`.

## Diagnostics

Every pipeline the demo builds counts what it does, and the pipeline HUD shows
the figures over any screen: tap the gauge in the navigation bar, or launch with
`-demoHUD 1`. The pill at the bottom opens into a panel with the tasks, cache
hits, queues, decode times, bytes, caches, memory footprint, and dropped frames
of the pipeline that is busy. **Pipeline HUD** in the Lab says what each figure
counts.

Launch the app with the `NUKE_DIAGNOSTICS_ENABLED` environment variable set – it is in
the scheme, unticked, under Run › Arguments › Environment Variables – and every
image task logs where its time went to Console, under the
`com.github.kean.NukeDemo` subsystem. The pipeline of the **Request Options**
screen records its tasks either way, and shows the record on screen.

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
├── App              The app, the catalog and Lab menus, the screen registry, and the launch arguments
├── Essentials       ImagePipeline, LazyImage, and the image views
├── Requests         Request options, priority, and thumbnails
├── Processing       Processors, image formats, and progressive decoding
├── Caching          Caching and prefetching
├── AnimatedImages   Animated image playback and its diagnostics
├── Integration      The pipeline delegate
├── Lab              Stress rigs and instruments for working on Nuke
├── Helpers          Shared views, the pipeline probe and HUD, fixtures, demo URLs, and a few small utilities
└── Resources        The app icon, the logo, a bundled animation, the bundled fixtures, and the photo stream's URLs
```
