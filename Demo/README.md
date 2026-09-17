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
| **Getting Started** | The snippets the README and the documentation open with, each running under its code: `ImagePipeline.shared.imageTask(with:)` with its progress, `LazyImage(url:)`, and `loadImage(with:into:)` with a `UIImageView`. They load one photo in turn, so the second and third find it in the memory cache. It is the catalog's first row, and on an iPad it runs beside the catalog from launch |
| **Image Pipeline** | `ImagePipeline.imageTask(with:)`, the event stream, progress, cancellation, and where the response came from, then the same image's bytes alone with `data(for:)`: their size, type, source, and time. A failure reads as the loader's error code and what it said |
| **LazyImage** | The SwiftUI view: loading states and failures, transitions, processors, priority, and completion. Then `FetchImage`, the observable object `LazyImage` is built on, in a view of its own with a progress bar, the result in words, and Load and Reset |
| **UIKit Views** | `loadImage(with:options:into:)` next to `LazyImageView` in a collection view, on a picker: with the extension you own the placeholder, the failure image, and the transition; `LazyImageView` owns them. Cell reuse either way |

### Requests

| Screen | Shows |
|--|--|
| **Request Options** | One image and a panel of every `ImageRequest.Options` flag, the priority, and a thumbnail next to a resize processor. Each change runs the request again and shows where the image came from, what it cost in time, bytes, and memory, and the stages the task went through, read from its `ImageTask.Metrics` |
| **Priority & Coalescing** | Twenty requests for six photos against a data loading queue of two slots: a counter of tasks and downloads, the downloads running and waiting in the order they will start, and a priority on every request that moves its download in the line. Hold suspends the queue, and one request shows what `.skipDataLoadingQueue` does when its URL is already loading |

### Processing & Formats

| Screen | Shows |
|--|--|
| **Image Processing** | The built-in processors and two ways to write your own, each tile with the bitmap it was decoded from, the image it became with its memory cost and time, read from its `ImageTask.Metrics`, and the disk cache key it is stored under. A thumbnail sits beside the resize: the same size, without the full-size decode |
| **Image Formats** | JPEG, PNG, WebP, HEIC, an animated GIF, and an APNG, each with what the pipeline made of its data: the MIME type it was served with, the type the decoder read in the data, the decoder `ImageDecoderRegistry` picked, and what Image I/O reads in the file's header |
| **Custom Decoder** | `NukePixDecoder`, a decoder for a toy format made up for the demo, registered in `ImageDecoderRegistry.shared` while the screen is open, with its code in the info sheet. Three files, loaded without the decoder and with it: a NukePix file, which only the new decoder reads; the same file cut short, which the decoder takes by its first bytes and fails; and a PNG, which it passes on to `ImageDecoders.Default`. Each shows its first bytes, what Image I/O makes of it, the decoder the registry picked, and the result |
| **Progressive Decoding** | The scans of a progressive JPEG, with a throttled data loader that makes them visible, and the number of previews decoded so far. A restart resumes the download and says from where |

### Caching & Performance

| Screen | Shows |
|--|--|
| **Caching** | Three requests – an original, a resize, and a thumbnail – loaded into the memory cache and `URLCache` or `DataCache`: the files each `DataCachePolicy` leaves on disk and their keys, what `.disableDiskCacheWrites` doesn't stop, and the `pipeline.cache` calls that read and write the same entries |
| **Prefetching** | `ImagePrefetcher` driven by `UICollectionViewDataSourcePrefetching` and by a SwiftUI grid, with its destination and priority on menus, and a count of the images each cell found in memory or on disk when it asked. The order the prefetcher starts its downloads in shows that at `.low` it works back from the far end of a batch |
| **Resumable Downloads** | A photo handed to the pipeline a few kilobytes at a time: cancel it partway and resume, and see the `Range` request that goes out, the `206 Partial Content` that comes back, and the bytes that weren't downloaded twice. Two switches show when a download can't resume: a server without validators, and a new pipeline |
| **Decompression** | A grid of 12 MP images, two to a row (three on an iPad), each under a URL of its own, with decompression off, on, on with `isUsingPrepareForDisplay`, and replaced by thumbnails. Auto-Scroll scrolls it at a fixed speed on a new pipeline for each, and each keeps its last run: the frames the main thread dropped, hitch time, the longest frame, the images shown, and the probe's decode and decompression times. A memory cache of four images, and cells that let go of theirs as they leave the screen, keep it within what a phone can hold |

### Animated Images

| Screen | Shows |
|--|--|
| **Animated Images** | GIF, APNG, WebP, and HEIC playback, and a GIF whose delays differ, with live diagnostics – the frame buffer, decode times, and dropped frames – in an inspector: beside the animation on iPad, in a sheet below it on iPhone. The buffer budget, the size the frames are decoded at, the rate, the repeat count, and a scrubber |

### Integration

| Screen | Shows |
|--|--|
| **Pipeline Delegate** | A delegate that adds a header in `willLoadData`, leaves a URL token out of `cacheKey`, and keeps a private photo off the disk in `willCache`, with a live log of what the pipeline asks it |
| **Custom Data Loader** | Three `DataLoading` implementations on a picker – a throttled download, a file from the app bundle picked by the delegate, and a server that fails – loading the same image on a new pipeline each run, with every call between the pipeline and the loader: the chunks, the pipeline's cancel, and the one `completion`. A throttled load cancelled partway never completes, and the screen shows the data loading slot and the pipeline it keeps |
| **Video** | `ImageDecoders.Video` from NukeVideo, which the app registers at launch: one request for an MP4 gives a poster frame and an `AVAsset`, and `VideoPlayerView` plays the asset in `LazyImage`'s content, over the poster until its first frame is up. What the memory and disk caches keep of a video, and the check for a file the decoder takes no frame from, which it reports as a success |

## Lab

Instruments and torture rigs for whoever works on Nuke, behind the last row of
the catalog. Caches are disabled on purpose and budgets pushed past sensible
values, and the screens report numbers rather than explain an API – the catalog
screen for that API does the explaining.

| Screen | Group | Shows |
|--|--|--|
| **Pipeline HUD** | Instruments | Every figure behind the HUD – tasks, coalescing, cache hits, queues, decode times, bytes, caches, footprint, and frames – for each pipeline and all of them, with the switch and a reset |
| **Concurrency Inspector** | Instruments | A burst, a trickle, or a scroll of fixture requests – photos, blurred photos, thumbnails, a 12 MP JPEG, and pairs – on a pipeline of its own, with pause and cancel: a map and a list of every task and where it is (queued, loading, receiving, waiting for or on a queue, finished), with its priority and age; the five task queues with the work running and waiting, how long work waited, and a limit and a suspend switch each; the queues of every pipeline alive; and the main thread's stalls over 16 ms, from a display link and a thread that pings the main queue, with buttons that stall it |
| **Scroll Stress** | Stress | The pipeline under fast scrolling with every cache disabled, on fixtures or over the network, with the HUD on and a frame counter of its own. Auto-Scroll scrolls at a fixed speed for 10 s and keeps each source's last run – frames dropped, hitch time, the longest frame, and the tasks started, cancelled, and finished – so runs, and fixtures and the network, can be compared |
| **Cancellation Torture** | Stress | Image tasks started at 200 a second for five seconds and cancelled before they start, while they wait, mid-download, and after they finish – plain, processed, thumbnail, progressive, and coalesced requests, heard through events, an awaited response, and closures – then pass or fail on: no callbacks after cancel, every task finished once, no `ImageTask` left, queues back to zero, survivors got their image, a new request completes, the pipeline goes away, and the rate reached. A slot check shows what a loader that follows the documented cancel contract does to the data loading queue |
| **Memory Soak** | Stress | A five-second cycle – 150 loads of the 12 MP JPEG, processed photos, and thumbnails, a third of them cancelled, six animations made and dropped, and a cache churned or a memory warning posted – repeated for 1, 5, 15, or 60 minutes, with the app's footprint drawn twice a second. After each cycle both caches are emptied and the footprint and the `malloc` heap read: pass or fail on the slope of each in MB a minute, on nothing left behind (tasks, players, animations, cache entries, files), on the pipelines alive, and on the memory warnings answered |
| **Cache Torture** | Stress | A 2 MB `DataCache` that sweeps every second, written, read, and removed from by a dozen tasks, then an `ImageCache` filled by eight threads at once, and pass or fail on: `sweep()` and the scheduled sweeps keeping `sizeLimit`, how far and how long it goes over, `flush()` latency, every read returning the last write, `removeAll()`, `ttl`, `entryCostLimit`, `costLimit` and `countLimit` under concurrent inserts, the trims, and the counts matching what the cache holds |
| **Animation Lab** | Animation | Up to 36 animations drawing from one `AnimatedImageFramePool` – the formats, from fixtures or the network, or the Fixture Zoo's animations with odd delays – with the pool's budget down to 4 MB, player budgets down to 256 KB, frames decoded at the size of the cell, zoom to 800%, frame transforms, and copies in and out of lockstep. A memory warning, and the minute until the windows grow back; power throttling against Low Power Mode, with each cell's frame rate; and a soak that plays for an hour, rebuilding the wall every minute, and charts the footprint and the pool |
| **Fixture Zoo** | Fixtures | Thirty inputs the decoders should survive – a 1×1, a 20,000 px canvas, CMYK, 16-bit, EXIF-rotated, zero-delay and broken animations, HEICS, AVIS, cut-off files, and files that aren't images – each decoded through a pipeline with no caches and reported as decoded, refused, or crashed next to what was expected, with the size, frames, decoder, decode time, and memory cost. A crash mid-decode is caught on the next launch. A regression sheet to screenshot |
| **Fixture Mode** | Rig | The switch that takes the whole demo offline, and every fixture with its size, the time it took to make, and a digest |
| **Network Conditions** | Rig | The switch that puts every download through latency, a shared bandwidth cap, lost requests, 500s, and cut-off bodies, with presets, the counts of what it did, and what the pipelines' diagnostics lose while it is on |
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
| `-demoNetwork <preset>` | Starts the app with [network conditions](#network-conditions) on: `slow-3g`, `lossy`, or `flaky-server`. `off`, the default, leaves the network as it is; a preset that doesn't exist does too, and logs why |
| `-demoAutorun 1` | Starts the run of a screen that has one as soon as it opens, once per launch: Decompression scrolls in each configuration, Concurrency Inspector starts a burst, Scroll Stress scrolls, Cancellation Torture runs its checks and the slot check, Memory Soak runs for a minute, Cache Torture runs its checks, and Animation Lab starts its soak |

The **Automation** screen in the Lab lists every id. An id stays the same when a
title changes.

## Fixtures

Offline, the demo loads no image from the network. Every URL it hands out is a
fixture's, `demo-fixture://nuke/<name>`: a stand-in for each photo with its
index drawn on it, a baseline and a progressive JPEG, a 12 MP JPEG, a PNG, a
HEIC, two GIFs (the long one has 200 frames), and an APNG, all drawn and
encoded the first time a load asks for them, plus a WebP, an animated WebP, and
a video bundled in `Resources/Fixtures`. The generated ones are the same bytes
on every run, so a run on fixtures can be compared with the last one.

Every pipeline's delegate sends a request for a fixture, and every request
while offline, to the fixture loader, which also answers the demo's network
URLs with their stand-ins; any other URL fails and says so in Console, under
the `Fixtures` category. It answers the way a server that supports range
requests does, so a download cancelled offline resumes too. A loader that never
goes to the network, such as the bundle and failing loaders of **Custom Data
Loader**, keeps its requests offline. Launch with `-demoFixtures offline`, or flip the switch
in **Fixture Mode** in the Lab, which applies to the screens opened next. Lab
screens that load photos start on fixtures either way.

The photo stream's URLs are in `Resources/photos.json`.

**Custom Decoder** loads two NukePix files, its toy format, the same way,
online and offline: `demo-fixture://nuke/badge.nukepix`, and the same file cut
short.

**Fixture Zoo** in the Lab serves its inputs the same way, as
`demo-fixture://nuke/zoo-<name>`: six files copied from `Tests/Resources` into
`Resources/Zoo`, the bundled HEICS, and the rest generated, damaged, or written
byte by byte on first use. `DemoZooInput` lists where each one comes from.

## Network conditions

**Network Conditions** in the Lab makes every catalog screen a test of its
failure states. While it is on, every pipeline's delegate puts the loader it
would have used – the configured one, or the fixture loader offline – behind a
rig that waits a latency, give or take a jitter, before each download, holds
all downloads to one shared bandwidth, and fails a share of them: lost
(`URLError.timedOut`), a server error (`DataLoader.Error.statusCodeUnacceptable(500)`,
as `DataLoader` reports a 500), or cut off partway through the body
(`URLError.networkConnectionLost`). The switch is read for every download, so
it applies to the next one with no pipeline rebuilt; off, nothing is wrapped.
A request that `URLCache` can answer goes through untouched.

Launch with `-demoNetwork slow-3g`, `lossy`, or `flaky-server`, and add
`-demoDeterministic 1` to fail the same downloads on every run. While the
conditions are on, `ImageTask.Metrics` has no `URLSession` metrics for the
downloads they touch; the HUD's figures are complete.

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
`com.github.kean.NukeDemo` subsystem. The pipelines of the **Request Options**,
**Priority & Coalescing**, **Image Processing**, **Caching**, **Resumable
Downloads**, and **Video** screens record their tasks either way, and show what
the records say on screen.

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
├── Essentials       Getting Started, ImagePipeline, LazyImage and FetchImage, and the image views
├── Requests         Request options, thumbnails, priority, and coalescing
├── Processing       Processors, image formats, a custom decoder, and progressive decoding
├── Caching          Caching, prefetching, resumable downloads, and decompression
├── AnimatedImages   Animated image playback and its diagnostics
├── Integration      The pipeline delegate, custom data loaders, and video
├── Lab              Instruments, stress rigs, the Fixture Zoo, and the rig's switches, for working on Nuke
├── Helpers          Shared views, the Lab's verdicts and sparkline, the pipeline probe and HUD, the frame and main-thread watchdogs, Auto-Scroll, fixtures, network conditions, demo URLs, the demo's data loaders, and a few small utilities
└── Resources        The app icon, the logo, a bundled animation, the bundled fixtures, the Fixture Zoo's copied inputs, and the photo stream's URLs
```
