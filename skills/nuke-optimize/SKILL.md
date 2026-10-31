---
name: nuke-optimize
description: Find out why images load slowly, scrolling stutters, memory grows, or the cache misses in an app that uses Nuke, and fix it. Use when asked to make images faster, to use less memory or data, to review how an app sets up Nuke, or to tune ImagePipeline, ImageCache, DataCache, ImagePrefetcher, or LazyImage. Covers Nuke 14, and what differs on 13.
license: MIT
---

# Optimizing Nuke

Nuke's defaults come from benchmarks, so the gains are almost always in how the app asks for images, and rarely in its configuration. A 12 MP photo decoded for a 120-point cell costs 46 MB, and no setting makes up for that.

Measure first, change one thing, and measure again. Each change here has a cost, and some make things worse when the cause is something else. If you can't run the app, say that what you changed comes from reading the code, and that it's unmeasured. For the API in general, see `llms-full.txt` at the root of the package.

## Measure

Launch with `NUKE_DIAGNOSTICS_LOG=1`, in the scheme or like this, and read one line per task:

```bash
SIMCTL_CHILD_NUKE_DIAGNOSTICS_LOG=1 xcrun simctl launch booted <bundle-id>
xcrun simctl spawn booted log stream --predicate 'subsystem == "com.github.kean.Nuke.ImagePipeline"'
```

```
ImageTask #1 · success · 78.5 ms · from network · https://example.com/a.png · 1200×800 · png · 3.7 MB in memory · 70 KB
```

Go through the slow screen twice: once on a fresh install, and again after relaunching.

| In the log | It means | Go to |
|---|---|---|
| `from network` after a relaunch | The disk cache missed | [Cache keys](#cache-keys), [Disk cache](#disk-cache) |
| `from httpCache`, and tens of ms | `URLCache` asked the server whether the image changed | [Disk cache](#disk-cache) |
| `MB in memory` over width × height × 4 of the cell, in pixels | The image is bigger than what's displayed | [Decode less](#decode-less) |
| The same URL twice, with no `coalesced` | Two requests that differ, so nothing is shared | [Cache keys](#cache-keys), [Prefetching](#prefetching) |
| More lines than cells on screen, on open | Everything loads at once | [Load only what's on screen](#load-only-whats-on-screen) |
| A long list of `cancelled` | Normal while scrolling fast, and the rate limiter is handling it | Nothing |

For where the time of a slow task went:

```swift
let pipeline = ImagePipeline { $0.isDiagnosticsEnabled = true }
let task = pipeline.imageTask(with: url)
_ = try await task.image
print(task.metrics!.formatted([.header, .breakdown]))
```

```
time:  network 93.6 ms (66%) · process 42.5 ms (30%) · cache 0.5 ms · decode 0.3 ms · queue 0.1 ms · other 3.8 ms (3%)
```

| Largest share | Cause |
|---|---|
| `network` | The file is too big, it wasn't cached, or the app opened a new connection |
| `process`, `decode`, `decompress` | The image is bigger than it needs to be |
| `queue` | The task waited for a slot. Prefetching, or too many images at once |
| `rateLimit` | The app starts and cancels requests faster than 100 a second |

`isDiagnosticsEnabled` costs a few microseconds a task, and it sends signposts, so the same stages show up in Instruments under os_signpost. For a task that hangs, `po ImagePipeline.shared.diagnostics` in the debugger prints the queues and the memory cache.

## Read the code

```bash
# More than one pipeline, or one created in a view
grep -rnE 'ImagePipeline(\(| \{)' --include='*.swift' .
# Every image load: does each one know the size it's displayed at?
grep -rnE 'LazyImage\(|ImageLoader\.load|FetchImage\(|\.image\(for:|imageTask\(with:' --include='*.swift' .
# Disk I/O that blocks the caller, which is a problem on the main thread
grep -rnE 'cachedData\(|cachedImage\(|containsCachedImage|containsData\(|storeCachedImage' --include='*.swift' .
# Prefetchers, and whether they build the same request as the views
grep -rn 'ImagePrefetcher' --include='*.swift' .
# Defaults someone changed: find out why before you keep or remove them
grep -rnE 'isRateLimiterEnabled|isTaskCoalescingEnabled|isDecompressionEnabled|skipDecompression|isProgressiveDecodingEnabled|isResumableDataEnabled|TaskQueue\(|maxConcurrentTaskCount|costLimit|sizeLimit' --include='*.swift' .
# Processors of your own: is the identifier stable?
grep -rnE ': ImageProcessing\b' --include='*.swift' .
```

## What to fix, in the order it pays

### Download less

The cheapest image is the one the server resizes. If the CDN takes a size, as in `?w=360`, ask for the size you display. That saves the data, the decode, and the memory, and nothing below does all three.

A decoded image has a scale of 1, so a 360-pixel file is 360 points wide. If the view shows it at its natural size, or a processor of yours draws in points, set `request.scale` to the scale of the screen.

### Decode less

Tell the pipeline the size you display at, in the request or with `.processors`. A SwiftUI `.frame` doesn't: it scales a full-size bitmap on every draw.

```swift
LazyImage(url: url) { state in
    if let image = state.image {
        image.resizable().scaledToFill()
    } else {
        Color.secondary.opacity(0.2)
    }
}
.processors([.resize(size: CGSize(width: 120, height: 120))]) // Points, aspect fill by default
.frame(width: 120, height: 120)
.clipped()
```

A 12 MP image shown at 120 points on a 3x screen, with 16 loading at once. Peak is the memory used on top of the downloaded files. Every row leaves 0.4 MB in memory, or 46.5 MB with no size:

| | No size | `.resize(width: 120)` | `thumbnail`, `maxPixelSize: 360` |
|---|---|---|---|
| JPEG, CPU per image | 74 ms | 35 ms | 35 ms |
| JPEG, peak | 267 MB | 4 MB | 5 MB |
| HEIC, CPU per image | 174 ms | 185 ms | 161 ms |
| HEIC, peak | 272 MB | 191 MB | 7 MB |
| PNG, CPU per image | 95 ms | 107 ms | 116 ms |
| PNG, peak | 142 MB | 97 MB | 14 MB |

These are from generated images on an iOS 27 simulator, so use them for the ranking, and not as a budget. Downsampling is a memory win first: a 1200×800 JPEG takes the same 6 ms either way, and leaves 0.3 MB rather than 3.7 MB.

**Use `.resize` for JPEG, and `thumbnail` for anything else that's large**, such as photos people upload, which are HEIC on an iPhone. `.resize` decodes those at full size first, so a burst of them can end the app even though each one ends up small.

```swift
var request = ImageRequest(url: url)
request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 360) // Pixels, the longest side
```

- `maxPixelSize` is in pixels, and `.resize` takes points. `maxPixelSize: 120` on a 3x screen is blurry.
- `maxPixelSize` fits the longest side, so a cell that fills needs `ThumbnailOptions(size:unit:contentMode:)`, which has to read the image size first.
- A thumbnail shares the download with other requests for the same URL, but not the decode. Two `.resize` requests share both.

**Never add either one to a request that can be animated.** A processor drops the animation, and a `thumbnail` skips it, so a GIF becomes a still. See [Animated images](#animated-images).

A processor of your own has to keep the size too. `UIGraphicsImageRenderer` draws at the scale of the screen by default, so an image with a scale of 1 comes out with nine times the pixels on a 3x device. Pass a `format` with `format.scale = image.scale`.

### One pipeline

There should be one `ImagePipeline`, set at launch. A pipeline per view has a `DataLoader` of its own, so it has its own `URLSession`: no shared connections, so a TLS handshake per image, and no coalescing between views. Pass `ImagePipeline.shared`, or use the default.

Use a second pipeline only for images with different rules, such as private ones that stay off the disk. All pipelines share `ImageCache.shared` unless you give one its own.

### Cache keys

The default key is the URL, with its query, plus the processors, and two requests only share work if those match.

- **A URL with a token that changes:** every launch is a miss. Set `imageID`:

```swift
var request = ImageRequest(url: signedURL, processors: [.resize(width: 320)])
request.imageID = "photo-\(photo.id)" // Replaces the URL in the cache keys
```

- `imageID` keys Nuke's caches: `ImageCache` and `DataCache`. `URLCache` belongs to Foundation and uses the URL, so on the default pipeline a signed URL still misses on disk. It needs `.withDataCache`.
- If the URL asks the CDN for a size, put the size in `imageID` too. Otherwise two sizes share one entry.
- **A processor with a changing identifier:** nothing is ever a hit. The `identifier` has to be a constant that describes what the processor does, and not a `UUID()` or a date.
- **Sizes from `GeometryReader`:** each different width is a new image in every cache. Round the widths to a few sizes that the app actually uses.

### Disk cache

The default pipeline has `URLCache`, which follows `cache-control`, and is limited to 150 MB. Check which of these the images are, because the wrong one is a bug and not a slow screen:

| Images | Use | Why |
|---|---|---|
| Never change at a URL | `.withDataCache` | Faster, works offline, no revalidation |
| Can change at a stable URL, like an avatar | The default `URLCache` | `.withDataCache` ignores `cache-control`, and shows the old image until it's evicted |
| Both | A pipeline for each | The rules are per pipeline, and these two can't share one |

```swift
var configuration = ImagePipeline.Configuration.withDataCache(name: "com.example.images", sizeLimit: 500 * 1024 * 1024)
configuration.dataCachePolicy = .automatic
ImagePipeline.shared = ImagePipeline(configuration: configuration)
```

`ImageCache` doesn't read `cache-control` either: an image that changes at a stable URL stays in memory until it's evicted, however short its `max-age`. Give those a memory cache of their own, with a `ttl`, on a second pipeline. Pass it to the views with `.pipeline(Pipelines.avatars)`, and to a prefetcher with `ImagePrefetcher(pipeline: Pipelines.avatars)`:

```swift
enum Pipelines {
    static let avatars = ImagePipeline {
        let cache = ImageCache()
        cache.ttl = 120
        $0.imageCache = cache
    }
}
```

If images fall out of the cache while the app is in use, the limit is too small. That shows up as `from network` for images seen earlier in the session.

`dataCachePolicy` decides what's stored:

| Policy | Stores | Use when |
|---|---|---|
| `.storeOriginalData`, the default | The download | The app shows an image at several sizes. Each size is processed again after a relaunch |
| `.automatic` | The processed image, for a request with processors | Each URL is shown at one size. A relaunch skips the resize, and the disk holds less |
| `.storeAll` | Both | Several sizes, and the CPU matters more than the disk |

Under `.automatic`, a second size of the same URL goes back to the network, and a `.diskCache` prefetch of a request with processors stores nothing.

### Prefetching

```swift
private let prefetcher = ImagePrefetcher()

func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
    prefetcher.startPrefetching(with: indexPaths.map { makeRequest(for: items[$0.item]) })
}

func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
    prefetcher.stopPrefetching(with: indexPaths.map { makeRequest(for: items[$0.item]) })
}

private func makeRequest(for item: Item) -> ImageRequest {
    ImageRequest(url: item.url, processors: [.resize(width: 120)])
}
```

**The prefetcher and the view must build the same request.** With different processors, the image gets decoded and cached twice, and the prefetching does nothing for the view. Keep one function that makes the request, `imageID` included, and call it from both.

SwiftUI has no prefetch API, so start from `onAppear`. `startPrefetching` skips what's cached or already running, so repeated calls are cheap:

```swift
struct Feed: View {
    let items: [Item]
    @State private var prefetcher = ImagePrefetcher()

    var body: some View {
        List(items.indices, id: \.self) { index in
            LazyImage(request: makeRequest(for: items[index]))
                .onAppear {
                    let next = items.dropFirst(index + 1).prefix(8)
                    prefetcher.startPrefetching(with: next.map(makeRequest))
                }
        }
    }

    private func makeRequest(for item: Item) -> ImageRequest {
        ImageRequest(url: item.url, processors: [.resize(width: 120)])
    }
}
```

The prefetcher runs at `.low`, 2 at a time, and cancels what's left when it's deallocated, so keep one per screen. In a SwiftUI view it has to be in `@State`: a `let` is made again with the view, which cancels the work of the old one. Set `isPaused = true` when another screen covers it, or when `NWPath.isConstrained` says the user is saving data. `ImagePrefetcher(destination: .diskCache)` skips the decode, which suits large images, but it needs `.storeOriginalData` or `.storeAll`.

### Load only what's on screen

`LazyImage` starts when it appears, so a `VStack` of 500 rows in a `ScrollView` starts 500 requests. Use `List`, `LazyVStack`, or `LazyVGrid`.

`LazyImage` cancels when it disappears, which is right for fast scrolling, and an interrupted download resumes if the server supports it. For large images that a user is likely to scroll back to, keep them going:

```swift
LazyImage(url: url)
    .onDisappear(.lowerPriority)
```

For what matters most on the screen, use `.priority(.high)`, or `ImageRequest(url:, priority: .high)`. A running `ImageTask` takes a new priority with `task.priority = .low`, which suits the grid behind a full-screen image.

If the `queue` share is high for the images on screen, prefetching is holding slots. Low-priority work runs in at most 3 of the 6 slots. Reserve 4 for large images, or 0 to 2 if prefetching has to keep up with thumbnails:

```swift
ImagePipeline.shared = ImagePipeline {
    $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 6, reservedTaskCount: 4)
}
```

### Memory

`ImageCache` takes up to 15% of the device's memory, capped at 768 MB, and clears itself on a memory warning. High memory is nearly always oversized images, so fix those first. Then:

```swift
ImageCache.shared.costLimit = 100 * 1024 * 1024
```

The default comes from the device, not the process. **In an app extension or a widget, set the limit yourself**, because the default can be larger than all the memory the extension is allowed. It also has to load small images: one full-size 12 MP decode is 46 MB, over the limit of a widget, whatever the cache does. `ImageCache` refuses an image that takes more than 10% of its limit (`entryCostLimit`), so a small limit stops caching large images.

### The main thread

`pipeline.cache[request]` reads memory, and is safe anywhere. `cachedImage(for:)`, `containsCachedImage(for:)`, and `cachedData(for:)` read the disk by default, and `cachedImage` also decodes. Off the main thread, or limit it:

```swift
let cached = ImagePipeline.shared.cache.cachedImage(for: request, caches: [.memory])
```

Create URLs when you parse the data, not in a view: `URL(string:)` isn't free in a long list.

### Animated images

- The frames are decoded no larger than the view displays them, so don't resize. This saves memory and not CPU: a smaller frame takes the same time to decode.
- If a URL can be a GIF or a large still, skip the animations in a processor of your own:

```swift
struct ResizeStills: ImageProcessing {
    let resize = ImageProcessors.Resize(width: 320)

    var identifier: String { "com.example.stills" + resize.identifier }

    func process(_ image: PlatformImage) -> PlatformImage? {
        resize.process(image)
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
        guard container.animation == nil else { return container }
        return try resize.process(container, context: context)
    }
}
```

- If you control the assets, a short video with `NukeVideo` is usually smaller than a GIF, and it's decoded in hardware.
- For a screen full of animations, show stills until someone asks: use `state.image` in the `content` closure of `LazyImage`, or set `isPlaybackEnabled = false` on `AnimatedImageView`.
- The frames share a pool, `AnimatedImageFramePool`, sized at 5% of the device's memory, up to 128 MB. An animation that doesn't fit plays from a window of three frames, and pays to decode them on every loop.

## Leave these alone

Each of these has been measured, or exists for a reason. If the code has changed one, find out why, and restore the default unless it's explained.

| Setting | Don't |
|---|---|
| `isTaskCoalescingEnabled` | Turn it off. It's why two views of one image make one download |
| `isRateLimiterEnabled` | Turn it off. It only acts when requests start and cancel at a high rate |
| `isResumableDataEnabled` | Turn it off. It costs nothing unless a download is interrupted |
| `isDecompressionEnabled`, `.skipDecompression` | Disable them on iOS. The decode moves to the main thread, at the first draw |
| `isUsingPrepareForDisplay` | Disable it. It made decoding 41–45% faster on an iOS simulator |
| `dataLoadingQueue` | Raise it past 6. In a simulation with shared bandwidth, 7 slots saved 7% for large images and nothing on HTTP/1.1. Use `reservedTaskCount` instead |
| `imageProcessingQueue`, `imageDecompressingQueue` | Raise them. They compete with the main thread for CPU |
| `isProgressiveDecodingEnabled` | Enable it for thumbnails. A progressive JPEG or a GIF gets decoded again every 0.5 s of its download |
| `isAnimatedImageParsingEnabled` | Disable it for speed. It only runs for animated data |
| `LazyImage` | Replace it with something hand-written for speed. It costs about 80 µs a cell over a plain `Image`, and the time is elsewhere |

## Report

Give the before and after for what you measured, and say which changes you couldn't measure. List the defaults you restored, and any trade-offs you took, such as stale images under `.withDataCache`.

## On Nuke 13

The log, `task.metrics`, and `diagnostics` don't exist, so measure with Instruments or Pulse, and read the code. `reservedTaskCount` doesn't exist. `isUsingPrepareForDisplay` is off, and turning it on is a free win. `TaskQueue` uses `maxConcurrentOperationCount`. Upgrading helps more than any of this: see the `nuke-migrate` skill.
