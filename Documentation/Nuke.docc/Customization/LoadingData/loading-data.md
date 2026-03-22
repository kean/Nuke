# Loading Data

Learn how pipeline loads data.

## Overview

``DataLoader`` uses [`URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) to load image data. The data is cached on disk using [`URLCache`](https://developer.apple.com/reference/foundation/urlcache), which by default is initialized with a memory capacity of 0 MB (Nuke only stores processed images in memory) and a disk capacity of 150 MB.

> Tip: See [Image Caching](https://kean.blog/post/image-caching) to learn more about HTTP cache. To learn more about caching in Nuke and how to configure it, see <doc:caching>.

The `URLSession` class natively supports the following URL schemes: `data`, `file`, `ftp`, `http`, and `https`.

The default ``DataLoader`` works great for most situations, but if you need to provide a custom networking layer, you can use a ``DataLoading`` protocol. See also, [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin).

## Intercepting Requests

To modify a URL request just before it is sent — for example, to inject authentication tokens or sign requests — implement ``ImagePipeline/Delegate-swift.protocol/willLoadData(for:urlRequest:pipeline:)`` in your pipeline delegate:

```swift
final class AuthenticatedPipelineDelegate: ImagePipeline.Delegate {
    func willLoadData(
        for request: ImageRequest,
        urlRequest: URLRequest,
        pipeline: ImagePipeline
    ) async throws -> URLRequest {
        var urlRequest = urlRequest
        let token = try await TokenStore.shared.validToken() // async, throws on failure
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return urlRequest
    }
}

let pipeline = ImagePipeline(delegate: AuthenticatedPipelineDelegate()) {
    // ...
}
```

The method is called on every URL-based request, after resumable data headers are applied but before the request is passed to ``DataLoading``. Throwing an error cancels the request and surfaces the error as ``ImagePipeline/Error/dataLoadingFailed(error:)``. The hook is not called for requests that use a custom data fetch closure or that target local file resources.

## Monitoring Network Requests

Nuke can be used with [Pulse](https://github.com/kean/Pulse) for monitoring network traffic.

```swift
(ImagePipeline.shared.configuration.dataLoader as? DataLoader)?.delegate = URLSessionProxyDelegate()
```

The same ``DataLoader/delegate`` can be used for modifying data loader behavior, e.g. for handling authentication requests and other aspects of data loading. 

```swift
// The delegate is retained by the `DataLoader`.
(ImagePipeline.shared.configuration.dataLoader as? DataLoader)?.delegate = YourDelegate()

final class YourDelegate: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Handle authentication challenge...
    }
}
```

## Resumable Downloads

If the data task is terminated when the image is partially loaded (either because of a failure or a cancellation), the next load will resume where the previous one left off. Resumable downloads require the server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators: `ETag` and `Last-Modified`. Resumable downloads are enabled by default. You can learn more in ["Resumable Downloads"](https://kean.blog/post/resumable-downloads).

## Custom Networking Layer

If you'd like to use some other networking library or custom code, implement the ``DataLoading`` protocol.

### The DataLoading Protocol Contract

``DataLoading`` has a single method:

```swift
func loadData(
    with request: URLRequest,
    didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
    completion: @escaping @Sendable (Error?) -> Void
) -> any Cancellable
```

**Threading:** `didReceiveData` and `completion` can be called on any thread.

**Incremental delivery:** Call `didReceiveData` each time a new chunk arrives. Nuke uses these chunks for progressive decoding. Each call must include a `URLResponse` — pass the response you received from the first chunk onward.

**Completion:** Call `completion` exactly once when the load finishes. Pass `nil` on success, or an `Error` on failure. Do not call `didReceiveData` after calling `completion`.

**Cancellation:** Return a `Cancellable` whose `cancel()` method stops the underlying task and ensures neither `didReceiveData` nor `completion` are called after cancellation.

### Alamofire Example

An [Alamofire plugin](https://github.com/kean/Nuke-Alamofire-Plugin) is available, but here is how a minimal implementation looks to illustrate the protocol contract:

```swift
/// Implements data loading using Alamofire framework.
public class AlamofireDataLoader: Nuke.DataLoading {
    public let session: Alamofire.Session

    /// Initializes the receiver with a given Alamofire.SessionManager.
    /// - parameter session: Alamofire.Session.default by default.
    public init(session: Alamofire.Session = Alamofire.Session.default) {
        self.session = session
    }

    // MARK: DataLoading

    /// Loads data using Alamofire.SessionManager.
    public func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let task = self.session.streamRequest(request)
        task.responseStream { [weak task] stream in
            switch stream.event {
            case let .stream(result):
                switch result {
                case let .success(data):
                    if let response = task?.response {
                        didReceiveData(data, response)
                    }
                }
            case let .complete(response):
                completion(response.error)
            }
        }
        .resume()
        return task
    }
}

extension Alamofire.Request: Nuke.Cancellable {}
```

## Topics

### Data Loader

- ``DataLoading``
- ``DataLoader``
