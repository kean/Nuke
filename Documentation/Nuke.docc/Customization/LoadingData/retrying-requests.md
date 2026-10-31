# Retrying Failed Requests

Recover from a dropped connection or a server having a bad moment without writing any loading code.

## Overview

Retries are off by default, because how long an image is worth waiting for is up to the app. To turn them on, set a ``ImagePipeline/RetryPolicy`` on the pipeline:

```swift
ImagePipeline.shared = ImagePipeline {
    $0.retryPolicy = .default
}
```

With the default policy, a load that fails for a reason that can go away is tried two more times, about 0.5 s and 1 s apart. `LazyImage` and the other views need no changes: they stay in the loading state until the pipeline gets the image or gives up.

## What Gets Retried

The policy retries what a second attempt can fix:

- The URL errors that mean that the connection failed or dropped out, listed in ``ImagePipeline/RetryPolicy/retryableURLErrorCodes``
- The status codes `408`, `429`, `500`, `502`, `503`, and `504`, listed in ``ImagePipeline/RetryPolicy/retryableStatusCodes``

It leaves alone what would fail the same way again:

- The rest of the failed responses, such as a `404`
- A request that isn't idempotent, such as a `POST`
- A failure caused by Low Data Mode, or by a restriction on expensive networks
- A failure to decode or process an image: the same data would fail again
- A local resource

The policy recognizes the errors of ``DataLoader`` and `URLError`, whichever data loader or `data` closure they come from. To retry other errors, implement ``ImagePipeline/Delegate-swift.protocol/retryDecision(for:pipeline:)``.

## Changing the Policy

```swift
var policy = ImagePipeline.RetryPolicy.default
policy.maxRetryCount = 4
policy.backoff = .exponential(initial: 1, multiplier: 3)
policy.retryableStatusCodes.insert(404) // A CDN that takes a moment to catch up

let pipeline = ImagePipeline {
    $0.retryPolicy = policy
}
```

The delays have ``ImagePipeline/RetryPolicy/jitter`` applied to them. When a host goes down, every image on the screen fails at the same time, and the jitter keeps them from all coming back at the same time.

If a response has a `Retry-After` header, the pipeline waits for at least as long as it says. If the server asks to wait for longer than ``ImagePipeline/RetryPolicy/maximumDelay``, the request fails instead of keeping the task around for an image nobody is going to wait for.

## Retrying a Single Request

``ImageRequest/retryPolicy`` replaces the policy of the pipeline for a request. Use it to try harder for the images that matter, or to skip the retries for the ones that don't:

```swift
var hero = ImageRequest(url: heroURL)
hero.retryPolicy = ImagePipeline.RetryPolicy(maxRetryCount: 5)

var thumbnail = ImageRequest(url: thumbnailURL)
thumbnail.retryPolicy = .disabled
```

## Waiting for the Network

Retrying while the device is offline only spends the attempts, so a load that fails because of it waits for the device to get back online, for up to ``ImagePipeline/RetryPolicy/connectivityTimeout``, and then continues right away. If the time runs out, the load fails with the original error. A subway tunnel is the classic case: images fill in on their own at the next station.

Set the timeout to `0` to treat these failures the same way as the rest.

## Deciding in the Delegate

Implement ``ImagePipeline/Delegate-swift.protocol/retryDecision(for:pipeline:)`` for what a policy can't express. The method can suspend, so it can also fix what went wrong. Every attempt goes through ``ImagePipeline/Delegate-swift.protocol/willLoadData(for:urlRequest:pipeline:)``, so this is all it takes to refresh an expired token:

```swift
final class AuthenticatedPipelineDelegate: Sendable {}

extension AuthenticatedPipelineDelegate: ImagePipeline.Delegate {
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        var urlRequest = urlRequest
        urlRequest.setValue("Bearer \(await TokenStore.shared.token)", forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    func retryDecision(for context: ImagePipeline.RetryContext, pipeline: ImagePipeline) async -> ImagePipeline.RetryDecision {
        if context.statusCode == 401, context.retryCount == 0 {
            await TokenStore.shared.refresh()
            return .retry(after: 0)
        }
        return context.policy?.decision(for: context) ?? .stop
    }
}
```

The last line falls back to the policy, which is what the default implementation does. The delegate has the last word, so ``ImagePipeline/RetryPolicy/maxRetryCount`` doesn't limit what it decides: check ``ImagePipeline/RetryContext/retryCount`` if it can return a retry for the same failure more than once.

> Tip: Throwing from `willLoadData` fails the request without asking about a retry. It's how the delegate says no.

## How Retries Fit into the Pipeline

A retry repeats the fetch of the data, and nothing around it, so the rest of the pipeline works the way it always does:

- **Coalescing.** Requests for the same image share the load, and with it the retries. Twenty cells with the same avatar make one sequence of requests, and the delegate is asked once per failed attempt. Requests can join while the load waits. If the requests have different policies, the one that allows the most retries applies.
- **Queues.** A load that is waiting doesn't take up a slot in ``ImagePipeline/Configuration-swift.struct/dataLoadingQueue``, so a host that is down doesn't hold up the images from the hosts that work. Each attempt goes through the queue again, at the current priority.
- **Cancellation.** Cancelling a task stops the wait right away, unless other tasks are waiting for the same load.
- **Resumable downloads.** If the server supports it, a retry continues from where the failed attempt stopped. Otherwise, it starts over, and the progress goes back with it. See ``ImagePipeline/Configuration-swift.struct/isResumableDataEnabled``.
- **Prefetching.** ``ImagePrefetcher`` doesn't use the policy of the pipeline: prefetching is speculative, and it isn't worth the battery. Set a policy on the request to retry a prefetch. If a request for the image joins it, its policy applies.

## Observing Retries

``ImageTask/Status/retryCount`` says how many times the load started over while the task waited for it. With ``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled`` on, ``ImageTask/Metrics`` has the rest: ``ImageTask/Metrics/retryCount``, the ``ImageTask/Metrics/Category/retry`` share of the time, and a download stage per attempt with the error it failed with.

```
j1 loadImage                478.2 ms
└─ j2 fetchOriginalImage    478.2 ms
   ├─ j3 fetchOriginalData  477.8 ms
   │  ├─ dataLoadingQueue     1.5 ms
   │  ├─ download            48.6 ms  network · 0 bytes · HTTP 503 · dataLoadingFailed
   │  ├─ retryDelay         426.6 ms
   │  └─ download             0.4 ms  network · 23 KB · HTTP 200 · first byte 0.3 ms
   └─ decode                  0.3 ms  ImageDecoders.Default · jpeg 640×480
```

A task that is waiting to retry says so in ``ImagePipeline/Diagnostics-swift.struct/snapshot()``, and ``ImageTask/Metrics/summary`` ends with the number of retries. See <doc:troubleshooting>.

## Retrying on Request

Once the pipeline gives up, it's up to the person looking at the screen. All the views can repeat the last load:

```swift
LazyImage(url: url) { state in
    if let image = state.image {
        image.resizable().scaledToFill()
    } else if state.error != nil {
        Button("Try Again") { state.reload() }
    } else {
        ProgressView()
    }
}
```

The same method is on `FetchImage`, `LazyImageView`, and `ImageLoader`.
