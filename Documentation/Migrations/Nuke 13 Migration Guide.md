# Nuke 13 Migration Guide

This guide eases the transition of the existing apps that use Nuke 12.x to the latest version of the framework.

## Minimum Requirements

The minimum supported platforms have been raised.

- iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, visionOS 1.0
- Xcode 26.0
- Swift 6.2

## DataLoading Protocol

The `DataLoading` protocol has been rewritten to use async/await and `AsyncThrowingStream` instead of callbacks. The `Cancellable` protocol has been removed.

```swift
// Before (Nuke 12)
public protocol DataLoading: Sendable {
    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable
}

public protocol Cancellable: AnyObject, Sendable {
    func cancel()
}

// After (Nuke 13)
public protocol DataLoading: Sendable {
    func loadData(with request: URLRequest) async throws -> (AsyncThrowingStream<Data, Error>, URLResponse)
}
```

If you have a custom `DataLoading` implementation, update it to return an `AsyncThrowingStream` that delivers data chunks, along with the initial `URLResponse`. The built-in `DataLoader` has been updated accordingly.

## Typed Throws

`ImageTask.image`, `ImageTask.response`, `ImagePipeline.image(for:)`, and `ImagePipeline.data(for:)` now use typed throws (`throws(ImagePipeline.Error)`). Two new error cases have also been added:

- `ImagePipeline.Error.cancelled` — thrown when a task is cancelled (previously `CancellationError`)
- `ImagePipeline.Error.dataDownloadExceededMaximumSize` — thrown when a download exceeds `Configuration.maximumResponseDataSize`

```swift
// Before (Nuke 12)
do {
    let image = try await ImagePipeline.shared.image(for: url)
} catch let error as ImagePipeline.Error {
    // handle pipeline error
} catch {
    // handle other errors, including CancellationError
}

// After (Nuke 13)
do {
    let image = try await ImagePipeline.shared.image(for: url)
} catch {
    // error is always ImagePipeline.Error
    switch error {
    case .cancelled: break
    case .dataLoadingFailed: break
    // ...
    }
}
```

## ImageRequest: Type-Safe Properties

Three `userInfo` dictionary keys have been replaced with dedicated, type-safe properties on `ImageRequest`. The old keys are deprecated.

```swift
// Before (Nuke 12)
var request = ImageRequest(url: url)
request.userInfo[.imageIdKey] = "http://example.com/image.jpeg"
request.userInfo[.scaleKey] = 2.0 as Float
request.userInfo[.thumbnailKey] = ImageRequest.ThumbnailOptions(maxPixelSize: 400)

// After (Nuke 13)
var request = ImageRequest(url: url)
request.imageID = "http://example.com/image.jpeg"
request.scale = 2.0
request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
```

Note that the existing `imageId` property has been renamed to `imageID` (uppercase "ID") and is now writable. The old `imageId` is deprecated.

```swift
// Before (Nuke 12)
let id: String? = request.imageId // read-only

// After (Nuke 13)
var id: String? = request.imageID // read/write
```

The `userInfo` dictionary type has also changed from `[UserInfoKey: Any]` to `[UserInfoKey: any Sendable]`.

## ImagePipeline.Delegate (Renamed from ImagePipelineDelegate)

`ImagePipelineDelegate` has been renamed to `ImagePipeline.Delegate` and is now defined as a nested type. A deprecated typealias is provided for backward compatibility, but you should update your code.

```swift
// Before (Nuke 12)
final class MyDelegate: ImagePipelineDelegate { ... }

// After (Nuke 13)
final class MyDelegate: ImagePipeline.Delegate { ... }
```

Several soft-deprecated per-event delegate methods have been fully removed. Use `imageTask(_:didReceiveEvent:pipeline:)` instead:

```swift
// Before (Nuke 12) — these methods no longer exist
func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) { ... }
func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress, pipeline: ImagePipeline) { ... }
func imageTask(_ task: ImageTask, didReceivePreview response: ImageResponse, pipeline: ImagePipeline) { ... }
func imageTaskDidCancel(_ task: ImageTask, pipeline: ImagePipeline) { ... }
func imageTask(_ task: ImageTask, didCompleteWithResult result: Result<ImageResponse, ImagePipeline.Error>, pipeline: ImagePipeline) { ... }

// After (Nuke 13)
func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
    switch event {
    case .started: break
    case .progress(let progress): break
    case .preview(let response): break
    case .finished(let result): break
    }
}
```

## ImageTask.Event Changes

`ImageTask.Event.cancelled` has been removed. Cancellation is now uniformly represented as a failure result. Additionally, a new `.started` case has been added.

```swift
// Before (Nuke 12)
public enum Event: Sendable {
    case progress(Progress)
    case preview(ImageResponse)
    case cancelled
    case finished(Result<ImageResponse, ImagePipeline.Error>)
}

// After (Nuke 13)
@frozen public enum Event: Sendable {
    case started
    case progress(Progress)
    case preview(ImageResponse)
    case finished(Result<ImageResponse, ImagePipeline.Error>) // .cancelled → .finished(.failure(.cancelled))
}
```

If you were handling `.cancelled` explicitly, switch to checking for `.finished(.failure(.cancelled))`:

```swift
// Before (Nuke 12)
case .cancelled:
    handleCancellation()

// After (Nuke 13)
case .finished(.failure(.cancelled)):
    handleCancellation()
```

## Configuration: Queue Types Changed

The pipeline's work queues have changed type from `OperationQueue` to `TaskQueue`, a new custom type synchronized on `ImagePipelineActor`. It preserves some of the existing API signatures.

```swift
// Before (Nuke 12)
configuration.dataLoadingQueue.maxConcurrentOperationCount = 4
configuration.imageDecodingQueue.maxConcurrentOperationCount = 2

// After (Nuke 13)
configuration.dataLoadingQueue = TaskQueue(maxConcurrentOperationCount: 4)
configuration.imageDecodingQueue = TaskQueue(maxConcurrentOperationCount: 2)
```

The deprecated `callbackQueue` and `dataCachingQueue` properties have been fully removed.

## Configuration: New Properties

Several new configuration properties have been added:

- `progressiveDecodingInterval` — minimum interval between progressive decoding attempts (default: 0.5s)
- `maximumResponseDataSize` — downloads exceeding this limit are cancelled automatically (default: 10% of physical memory, capped at 200 MB)
- `maximumDecodedImageSize` — images whose decoded bitmap exceeds this limit are downscaled automatically (default: based on physical memory)

If you previously set no limits and want to preserve that behavior, set these to `nil`:

```swift
configuration.maximumResponseDataSize = nil
configuration.maximumDecodedImageSize = nil
```

## Callback Closures: @MainActor @Sendable

All callback closures in the public API are now annotated with `@MainActor @Sendable`. This is a source-breaking change if you pass closures that are not already main-actor isolated.

**ImagePipeline closure-based API:**

```swift
// Before (Nuke 12)
pipeline.loadImage(with: request) { result in
    self.imageView.image = try? result.get().image
}

// After (Nuke 13) — closure is @MainActor, self access is safe
pipeline.loadImage(with: request) { result in
    self.imageView.image = try? result.get().image
}
```

The closures are implicitly `@MainActor`, so capturing `self` without `[weak self]` will now produce a warning if `self` is not `@MainActor`. Update your closures accordingly.

**NukeUI callbacks** (`FetchImage`, `LazyImage`, `LazyImageView`):

```swift
// Before (Nuke 12)
lazyImageView.onSuccess = { response in
    print(response.image)
}

// After (Nuke 13) — same syntax, but now @MainActor @Sendable
lazyImageView.onSuccess = { response in
    print(response.image)
}
```
