# Errors

Handle the typed errors the pipeline throws.

## Overview

Every image request finishes with either an ``ImageResponse`` or an ``ImagePipeline/Error``. That's not a convention – it's in the signature. ``ImagePipeline/image(for:)-(URL)``, ``ImageTask/image``, and ``ImageTask/response`` are declared `throws(ImagePipeline.Error)`, so the error you catch is already the concrete type.

```swift
do {
    imageView.image = try await ImagePipeline.shared.image(for: url)
} catch {
    // `error` is an `ImagePipeline.Error` – no cast, no `as?`
    switch error {
    case .dataDownloadExceededMaximumSize:
        showTooLargeMessage()
    default:
        showFailureImage()
    }
}
```

The type reaches the views too. `NukeUI` doesn't erase it: `LazyImageState.error`, `FetchImage.result`, and the `onCompletion` closures all carry `ImagePipeline.Error`, so a view can branch on a case directly.

```swift
LazyImage(url: url) { state in
    if case .dataDownloadExceededMaximumSize = state.error {
        Text("Image too large")
    } else if let image = state.image {
        image.resizable()
    }
}
```

## Cancellation Is Not a Failure

``ImagePipeline/Error/cancelled`` is by far the most common case, and it almost never deserves an error message. Every image view that scrolls offscreen cancels its request; so does every `LazyImage` whose URL changes. Filter it out before you report anything.

```swift
do {
    imageView.image = try await ImagePipeline.shared.image(for: url)
} catch {
    guard !error.isCancelled else { return }
    logger.error("Failed to load image: \(error)")
}
```

``ImagePipeline/Error/isCancelled`` is the check to use. Reaching for `Task.isCancelled` instead misses the cancellations that come from ``ImageTask/cancel()``, and treating cancellation as a failure fills your logs and your UI with noise that isn't a bug.

> Tip: ``ImageTask/isCancelled`` answers a different question: it records whether cancellation was *requested*, which can happen after a task has already succeeded. Use the error to learn how the task actually ended.

## The Error Cases

| Case | When it happens |
|---|---|
| ``ImagePipeline/Error/cancelled`` | The task was cancelled, either by ``ImageTask/cancel()`` or by cancelling the Swift concurrency task awaiting it. |
| ``ImagePipeline/Error/dataLoadingFailed(error:)`` | The data loader failed. Wraps the underlying error – usually a `URLError`, or a ``DataLoader/Error`` for an unacceptable status code. |
| ``ImagePipeline/Error/dataIsEmpty`` | The download finished successfully but produced no bytes. |
| ``ImagePipeline/Error/dataMissingInCache`` | ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad`` was set and the data wasn't in the cache. |
| ``ImagePipeline/Error/dataDownloadExceededMaximumSize`` | The response grew past ``ImagePipeline/Configuration-swift.struct/maximumResponseDataSize``. The download is cancelled as soon as the limit is crossed. |
| ``ImagePipeline/Error/decoderNotRegistered(context:)`` | No decoder matched the downloaded data. Only reachable with custom decoders – ``ImageDecoders/Default`` is a catch-all otherwise. |
| ``ImagePipeline/Error/decodingFailed(decoder:context:error:)`` | The decoder ran but couldn't produce a final image, typically because the data is corrupt or truncated. |
| ``ImagePipeline/Error/processingFailed(processor:context:error:)`` | An ``ImageProcessing`` in the request failed. The failing processor is attached. |
| ``ImagePipeline/Error/imageRequestMissing`` | A view or ``ImagePipeline`` method was asked to load with no request – most often a `nil` URL reaching `LazyImage` or `loadImage(with:into:)`. |
| ``ImagePipeline/Error/pipelineInvalidated`` | The pipeline was invalidated with ``ImagePipeline/invalidate()``; it accepts no further requests. |

Every case is `CustomStringConvertible`, so `"\(error)"` gives you a description that already includes the underlying error where there is one.

## Unwrapping the Underlying Error

``ImagePipeline/Error/dataLoadingFailed(error:)`` is the only case that wraps something else, and it's the one you usually need to look inside – to tell "the device is offline" apart from "the server said 404". ``ImagePipeline/Error/dataLoadingError`` unwraps it for you, returning `nil` for every other case.

```swift
func message(for error: ImagePipeline.Error) -> String? {
    guard !error.isCancelled else { return nil }
    switch error.dataLoadingError {
    case let urlError as URLError where urlError.code == .notConnectedToInternet:
        return "You're offline"
    case let loaderError as DataLoader.Error:
        if case let .statusCodeUnacceptable(statusCode) = loaderError {
            return "Server returned \(statusCode)"
        }
        return "Couldn't load the image"
    default:
        return "Couldn't load the image"
    }
}
```

A `URLError` is what you get for the ordinary networking failures: no connection, a timeout, a TLS failure, a cancelled `URLSession` task. A ``DataLoader/Error`` is produced by ``DataLoader/validate(response:)``, which rejects any HTTP status code outside `2xx`.

An error thrown from ``ImagePipeline/Delegate/willLoadData(for:urlRequest:pipeline:)`` or from an async ``ImageRequest`` source is wrapped the same way, so a failed token refresh arrives as `dataLoadingFailed` carrying your own error type.
