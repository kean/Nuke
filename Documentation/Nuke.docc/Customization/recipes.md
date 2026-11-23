# Recipes

Fall back to another source, respect Low Data Mode, set how long an image stays cached, pin an image, limit its memory, and display HDR.

## Overview

Nuke has no option for any of these, but the pipeline has the hooks to build them: ``DataLoading``, ``ImagePipeline/Delegate-swift.protocol``, and ``ImageRequest/userInfo``. Each recipe starts with the smallest thing that works, so read until you have what you need. `LazyImage` is in NukeUI.

Retrying a failed download is built in: see <doc:retrying-requests>.

## Fall Back to Another Source

### In a View

The simplest fallback is another view, in the failure branch of the `content` closure. Each URL has its own entry in the caches.

```swift
struct AvatarView: View {
    let url: URL
    let fallback: URL

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else if state.error != nil {
                LazyImage(url: fallback)
            } else {
                Color.gray
            }
        }
    }
}
```

### In the Data Loader

To fall back in the pipeline, so that it works anywhere, wrap the data loader. The URLs travel with the request, and the delegate builds a loader for it:

```swift
extension ImageRequest.UserInfoKey {
    static let alternatives: ImageRequest.UserInfoKey = "com.example.alternatives"
}

/// Loads the request, and then each of `alternatives`, until one succeeds.
struct FallbackDataLoader: DataLoading {
    var base: any DataLoading
    var alternatives: [URL]

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let load = FallbackLoad()
        start(request, alternatives[...], load, didReceiveData, completion)
        return load
    }

    private func start(
        _ request: URLRequest,
        _ rest: ArraySlice<URL>,
        _ load: FallbackLoad,
        _ didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        _ completion: @escaping @Sendable (Error?) -> Void
    ) {
        let inner = base.loadData(with: request, didReceiveData: { data, response in
            load.didReceiveData()
            didReceiveData(data, response)
        }, completion: { error in
            guard error != nil, load.canFallBack, let url = rest.first else {
                return completion(error)
            }
            var next = request
            next.url = url
            start(next, rest.dropFirst(), load, didReceiveData, completion)
        })
        load.track(inner)
    }
}

/// The attempt in flight.
final class FallbackLoad: Cancellable {
    private struct State {
        var inner: (any Cancellable)?
        var hasData = false
        var isCancelled = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// The pipeline appends every chunk, so a source that delivered data can't
    /// be replaced by another one.
    var canFallBack: Bool { state.withLock { !$0.hasData && !$0.isCancelled } }

    func didReceiveData() {
        state.withLock { $0.hasData = true }
    }

    func track(_ inner: any Cancellable) {
        let isCancelled = state.withLock {
            $0.inner = inner
            return $0.isCancelled
        }
        if isCancelled { inner.cancel() }
    }

    func cancel() {
        let inner = state.withLock {
            $0.isCancelled = true
            return $0.inner
        }
        inner?.cancel()
    }
}

final class FallbackDelegate: Sendable {}

extension FallbackDelegate: ImagePipeline.Delegate {
    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
        FallbackDataLoader(
            base: pipeline.configuration.dataLoader,
            alternatives: request.userInfo[.alternatives] as? [URL] ?? []
        )
    }
}
```

```swift
let pipeline = ImagePipeline(delegate: FallbackDelegate())

var request = ImageRequest(url: url)
request.userInfo[.alternatives] = [mirror, secondMirror]
let image = try await pipeline.image(for: request)
```

The image is cached under the first URL, wherever it came from, so a later load finds it there. That's what you want when the sources are mirrors of one image. A source that fails halfway through fails the task, because the pipeline has already appended what it received.

## Low Data Mode

Set `allowsConstrainedNetworkAccess` to `false`, and a request fails instead of using the network while Low Data Mode is on. In a view, show a smaller image from there:

```swift
func isConstrained(_ error: ImagePipeline.Error?) -> Bool {
    (error?.dataLoadingError as? URLError)?.networkUnavailableReason == .constrained
}

struct LowDataImage: View {
    let url: URL
    let lowDataURL: URL

    private var request: ImageRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.allowsConstrainedNetworkAccess = false
        return ImageRequest(urlRequest: urlRequest)
    }

    var body: some View {
        LazyImage(request: request) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else if isConstrained(state.error) {
                LazyImage(url: lowDataURL)
            }
        }
    }
}
```

Do it in the view rather than in a data loader. A loader would cache the smaller image under the full-size URL, where it stays after the user leaves Low Data Mode. The view caches each one under its own URL.

## Per-Request Lifetime

The simplest way to set how long an image stays on disk is on the server. The default ``DataLoader`` uses `URLCache`, which follows the `Cache-Control` header of each response.

For the memory cache, give the requests that shouldn't stay long a cache with a ``ImageCache/ttl``:

```swift
extension ImageRequest.UserInfoKey {
    static let isShortLived: ImageRequest.UserInfoKey = "com.example.is-short-lived"
}

final class LifetimeDelegate: Sendable {
    let shortLived: ImageCache

    init(ttl: TimeInterval = 60) {
        shortLived = ImageCache()
        shortLived.ttl = ttl
    }
}

extension LifetimeDelegate: ImagePipeline.Delegate {
    func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)? {
        request.userInfo[.isShortLived] != nil ? shortLived : pipeline.configuration.imageCache
    }
}
```

``DataCache`` has no expiration, only a size limit. To give a group of images a share of the disk of their own, choose between two caches with ``ImagePipeline/Delegate-swift.protocol/dataCache(for:pipeline:)``, as the next recipe does.

## Pinning

To keep an image until you remove it, store it in a ``DataCache`` that never sweeps:

```swift
extension ImageRequest.UserInfoKey {
    static let isPinned: ImageRequest.UserInfoKey = "com.example.is-pinned"
}

final class PinningDelegate: Sendable {
    let regular: DataCache
    let pinned: DataCache

    init() throws {
        regular = try DataCache(name: "com.example.images")
        pinned = try DataCache(name: "com.example.pinned")
        pinned.isSweepEnabled = false
    }
}

extension PinningDelegate: ImagePipeline.Delegate {
    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)? {
        request.userInfo[.isPinned] != nil ? pinned : regular
    }
}
```

```swift
ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(), delegate: try PinningDelegate())
```

The pinned cache grows until you remove its entries, so give the user a way to do that. ``ImagePipeline/Configuration-swift.struct/withDataCache(name:sizeLimit:)`` also turns off `URLCache`, which would otherwise store every image a second time.

## Limit the Memory of an Image

An image can decode to far more memory than its file suggests. To cap it, limit the longest side with a thumbnail, which decodes the image at that size:

```swift
extension ImageRequest {
    /// Limits the longest side, so that a decoded image can't exceed `bytes`
    /// at 4 bytes per pixel. A square is the worst case.
    mutating func limitMemory(to bytes: Int) {
        thumbnail = ThumbnailOptions(maxPixelSize: floor(sqrt(CGFloat(bytes) / 4)))
    }
}
```

60 MB gives a longest side of 3965 pixels. A request with a thumbnail doesn't play animations, so keep it away from the requests that can be animated.

## HDR

On iOS, tvOS, and visionOS, an image that is HDR in itself, such as a PQ or an HLG HEIC or AVIF, stays HDR: ``ImagePipeline/Configuration-swift.struct/isUsingPrepareForDisplay`` keeps its depth. All it needs is a view that shows it:

```swift
imageView.preferredImageDynamicRange = .high
```

In SwiftUI, that's `allowedDynamicRange(.high)` on the `Image`. A processor, and decompression with `isUsingPrepareForDisplay` off, draw in 8 bits, which makes the image SDR.

An SDR image with a gain map is decoded as SDR unless the decoder asks for HDR:

```swift
@available(iOS 17, tvOS 17, *)
struct HDRDecoder: ImageDecoding {
    func decode(_ data: Data) throws -> ImageContainer {
        let options = [kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw ImageDecodingError.unknown
        }
        return ImageContainer(image: UIImage(cgImage: image))
    }
}

final class HDRDelegate: Sendable {}

@available(iOS 17, tvOS 17, *)
extension HDRDelegate: ImagePipeline.Delegate {
    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        context.isCompleted ? HDRDecoder() : nil
    }

    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
        false // Decompression can draw the image in 8 bits
    }
}
```

> Note: This one is a starting point. Check it on a device with your own images.
