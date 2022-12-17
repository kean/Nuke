# Loading Data

Learn how pipeline loads data.

## Overview

``DataLoader`` uses [`URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) to load image data. The data is cached on disk using [`URLCache`](https://developer.apple.com/reference/foundation/urlcache), which by default is initialized with a memory capacity of 0 MB (Nuke only stores processed images in memory) and disk capacity of 150 MB.

> Tip: See [Image Caching](https://kean.blog/post/image-caching) to learn more about HTTP cache. To learn more about caching in Nuke and how to configure it, see <doc:caching>.

The `URLSession` class natively supports the following URL schemes: `data`, `file`, `ftp`, `http`, and `https`.

The default ``DataLoader`` works great for most situation, but if you need to provide a custom networking layer, you can using a ``DataLoading`` protocol. See also, [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin).

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

If the data task is terminated when the image is partially loaded (either because of a failure or a cancellation), the next load will resume where the previous left off. Resumable downloads require the server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators: `ETag` and `Last-Modified`. Resumable downloads are enabled by default. You can learn more in ["Resumable Downloads"](https://kean.blog/post/resumable-downloads).

## Custom Networking Layer

If you'd like to use Alamofire for networking, it's easy to do thanks to an [Alamofire plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that allows you to load image data using [Alamofire.SessionManager](https://github.com/Alamofire/Alamofire).

If you'd like to use some other networking library or use your custom code, all you need to do is implement the ``DataLoading`` protocol consisting of a single method.

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
    public func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        let task = self.session.streamRequest(request)
        task.responseStream { [weak task] stream in
            switch stream.event {
            case let .stream(result):
                switch result {
                case let .success(data):
                    guard let response = task?.response else { return } // Never nil
                    didReceiveData(data, response)
                }
            case let .complete(response):
                completion(response.error)
            }
        }
        return AnyCancellable { task.cancel() }
    }
}
```

## Topics

### Data Loader

- ``DataLoading``
- ``DataLoader``
- ``Cancellable``
