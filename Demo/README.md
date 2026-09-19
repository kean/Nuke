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
and ends with the [Lab](#lab). Every screen has a question mark in the
navigation bar that explains what it shows, with the API it is about and the
details worth knowing.

### Essentials

| Screen | Shows |
|--|--|
| **LazyImage** | The SwiftUI view: loading states and failures, transitions, processors, priority, and completion. Then `FetchImage`, the observable object `LazyImage` is built on, in a view of its own with a progress bar, the result in words, and Load and Reset |
| **UIKit Views** | `loadImage(with:options:into:)` next to `LazyImageView` in a collection view, on a picker: with the extension you own the placeholder, the failure image, and the transition; `LazyImageView` owns them. Cell reuse either way |
| **Image Processing** | The built-in processors and two ways to write your own, each tile with the bitmap it was decoded from, the image it became with its memory cost and time, read from its `ImageTask.Metrics`, and the disk cache key it is stored under. A thumbnail sits beside the resize: the same size, without the full-size decode |

### Formats

| Screen | Shows |
|--|--|
| **Image Formats** | JPEG, PNG, WebP, HEIC, an animated GIF, and an APNG, each with what the pipeline made of its data: the MIME type it was served with, the type the decoder read in the data, the decoder `ImageDecoderRegistry` picked, and what Image I/O reads in the file's header |
| **Animated Images** | GIF, APNG, WebP, and HEIC playback, and a GIF whose delays differ, with live diagnostics – the frame buffer, decode times, and dropped frames – in an inspector: a column on iPad, which lies over the animation in portrait, and a sheet below it on iPhone. The buffer budget, the size the frames are decoded at, the rate, the repeat count, and a scrubber |
| **Progressive Decoding** | The scans of a progressive JPEG and the one pass of a baseline JPEG – side by side where the screen has room, on a picker where it doesn't – with a throttled data loader that makes them visible, and the number of previews decoded so far. A restart resumes the downloads and says from where |
| **Video** | `ImageDecoders.Video` from NukeVideo, which the app registers at launch: one request for an MP4 gives a poster frame and an `AVAsset`, and `VideoPlayerView` plays the asset in `LazyImage`'s content, over the poster until its first frame is up. What the memory and disk caches keep of a video, and the check for a file the decoder takes no frame from, which it reports as a success |

### Caching & Performance

| Screen | Shows |
|--|--|
| **Caching** | Three requests – an original, a resize, and a thumbnail – loaded into the memory cache and `URLCache` or `DataCache`: the files each `DataCachePolicy` leaves on disk and their keys, what `.disableDiskCacheWrites` doesn't stop, and the `pipeline.cache` calls that read and write the same entries |
| **Prefetching** | `ImagePrefetcher` driven by `UICollectionViewDataSourcePrefetching` and by a SwiftUI grid, with its destination and priority on menus, and a count of the images each cell found in memory or on disk when it asked. The order the prefetcher starts its downloads in shows that at `.low` it works back from the far end of a batch |
| **Decompression** | A grid of 12 MP images, two to a row (three on an iPad), each under a URL of its own, with decompression off, on, on with `isUsingPrepareForDisplay`, and replaced by thumbnails. Auto-Scroll scrolls it at a fixed speed on a new pipeline for each, and each keeps its last run: the frames the main thread dropped, hitch time, the longest frame, the footprint's peak, the images shown, and the probe's decode and decompression times. A memory cache of four images, and cells that let go of theirs as they leave the screen, keep it within what a phone can hold |

### Integration

| Screen | Shows |
|--|--|
| **Custom Decoder** | `NukePixDecoder`, a decoder for a toy format made up for the demo, registered in `ImageDecoderRegistry.shared` while the screen is open, with its code in the info sheet. Three files, loaded without the decoder and with it: a NukePix file, which only the new decoder reads; the same file cut short, which the decoder takes by its first bytes and fails; and a PNG, which it passes on to `ImageDecoders.Default`. Each shows its first bytes, what Image I/O makes of it, the decoder the registry picked, and the result |
| **Custom Data Loader** | Three `DataLoading` implementations on a picker – a throttled download, a file from the app bundle picked by the delegate, and a server that fails – loading the same image on a new pipeline each run, with every call between the pipeline and the loader: the chunks, the pipeline's cancel, and the one `completion`. A throttled load cancelled partway never completes, and the screen shows the data loading slot and the pipeline it keeps |

## Lab

Instruments and stress rigs for whoever works on Nuke, in the last section of
the catalog. Caches are turned off where they would hide the work, budgets are
pushed past sensible values, and the screens report numbers rather than explain
an API – the catalog screen for that API does the explaining.

| Screen | Shows |
|--|--|
| **Pipeline HUD** | The HUD's lines – tasks, where the images came from and the hit rate, queues, network bytes, the image cache and frame pool, disk, footprint, and frames – for each pipeline alive and all of them added up, with the switch, Expanded, and a reset |
| **Concurrency Inspector** | A burst of 240 fixture requests – photos, blurred photos, and thumbnails of a 12 MP JPEG – on a pipeline of its own, with cancel: a map of every task by where it is (waiting, loading, decoding, processing, decompressing, finished), and the five task queues with the work running against the limit and a suspend switch each |
| **Priority & Coalescing** | Twenty requests for six photos against a data loading queue of two slots: a counter of tasks and downloads, the downloads running and waiting in the order they will start, and a priority on every request that moves its download in the line. Hold suspends the queue, and one request shows what `.skipDataLoadingQueue` does when its URL is already loading |
| **Scroll Stress** | The pipeline under fast scrolling on fixtures with every cache disabled, ten images to a row, with the HUD on and a frame counter of its own. Auto-Scroll scrolls at a fixed speed for 10 s and keeps the last run – frames dropped, the longest frame, and the tasks started – so two builds can be compared |
| **Animation Lab** | Up to 36 animations playing at once from fixtures, drawing their frames from the shared `AnimatedImageFramePool`: the pool's budget from 4 to 256 MB, a memory warning with the pool before it and at its lowest, lockstep on and off, and each cell's frames and bytes buffered |

## Launch arguments

A few launch arguments open the app in a known state, so a script can take a
screenshot of any screen without tapping its way there. Pass them after the
bundle id, or add them under Edit Scheme › Run › Arguments Passed On Launch:

```bash
xcrun simctl launch booted com.github.kean.NukeDemo -demoScreen caching -demoLab 0
```

| Argument | Does |
|--|--|
| `-demoScreen <id>` | Opens the app on a screen, with the catalog beneath it. An id that no screen has opens the catalog and logs why |
| `-demoLab 0` | Leaves the Lab section out of the catalog, for a screenshot of the rest alone |
| `-demoHUD 1` | Opens the app with the pipeline HUD on, folded into its pill; `expanded` opens its panel |
| `-demoAutorun 1` | Starts the run of a screen that has one as soon as it opens, once per launch: Decompression scrolls in each configuration, Concurrency Inspector starts a burst, and Scroll Stress scrolls |

A screen's id is the raw value of its case in `App/DemoScreen.swift`. An id
stays the same when a title changes.

## Fixtures

The Lab screens load fixtures rather than the network by default, so that one
run measures what the last one did rather than the network in between. Each
fixture has a URL of its own, `demo-fixture://nuke/<name>`: a stand-in for each
photo with its index drawn on it, a baseline and a progressive JPEG, a 12 MP
JPEG, a PNG, a HEIC, three GIFs (the long one has 200 frames), and an APNG, all
drawn and encoded the first time a load asks for them, plus a WebP, an animated
WebP, and a video bundled in `Resources/Fixtures`. The generated ones are the
same bytes on every run.

Every pipeline's delegate sends a request for a fixture to the fixture loader;
any other URL goes to the loader the pipeline was configured with. The fixture
loader answers the way a server that supports range requests does, so a
download cancelled midway resumes too. In the catalog, **Custom Decoder** loads
its NukePix files this way, **Decompression** its 12 MP JPEG, and **Animated
Images** its GIF with mixed delays.

The photo stream's URLs are in `Resources/photos.json`.

## Diagnostics

Every pipeline the demo builds counts what it does, and the pipeline HUD shows
the figures over any screen: tap the gauge in the navigation bar, or launch with
`-demoHUD 1`. The pill at the bottom opens into a panel with the tasks, where
the images came from, the queues, bytes, caches, memory footprint, and dropped
frames of the pipeline that did something last. **Pipeline HUD** in the Lab
shows the same lines for every pipeline at once.

Launch the app with the `NUKE_DIAGNOSTICS_ENABLED` environment variable set – it is in
the scheme, unticked, under Run › Arguments › Environment Variables – and every
image task logs where its time went to Console, under the
`com.github.kean.NukeDemo` subsystem. The pipelines of the **Priority &
Coalescing**, **Image Processing**, **Caching**, and **Video** screens record
their tasks either way, and show what the records say on screen.

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
├── App              The app, the catalog, the screen registry, and the launch arguments
├── Essentials       LazyImage and FetchImage, the image views, and processors
├── Formats          Image formats, animated images, progressive decoding, and video
├── Caching          Caching, prefetching, and decompression
├── Integration      A custom decoder and custom data loaders
├── Lab              Instruments and stress rigs for working on Nuke, and priority and coalescing
├── Helpers          Shared views, the pipeline probe and HUD, the frame watchdog, Auto-Scroll, fixtures, demo URLs, the demo's data loaders, and a few small utilities
└── Resources        The app icon, the logo, a bundled animation, the bundled fixtures, and the photo stream's URLs
```
