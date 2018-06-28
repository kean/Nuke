### Using Other Networking Libraries

By default, Nuke uses a `Foundation.URLSession` for all the networking. Apps may have their own network layer they may wish to use instead.

Nuke already has an [Alamofire plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that allows you to load image data using [Alamofire.SessionManager](https://github.com/Alamofire/Alamofire). If you want to use Nuke with Alamofire simply follow the plugin's docs.

If you'd like to use some other networking library or use your own custom code all you need to do is implement `Nuke.DataLoading` protocol which consists of a single method:

```swift
/// Loads data.
public protocol DataLoading {
    /// Loads data with the given request.
    func loadData(with request: URLRequest,
                  token: CancellationToken?,
                  progress: ProgressHandler?,
                  completion: @escaping (Result<(Data, URLResponse)>) -> Void)
}
```

You can use [Alamofire plugin](https://github.com/kean/Nuke-Alamofire-Plugin) as a starting point. Here how it's actual implementation:

```swift
import Alamofire
import Nuke

class AlamofireDataLoader: Nuke.DataLoading {
    private let manager: Alamofire.SessionManager

    init(manager: Alamofire.SessionManager = Alamofire.SessionManager.default) {
        self.manager = manager
    }

    // MARK: Nuke.DataLoading

    /// Loads data using Alamofire.SessionManager.
    public func loadData(with request: URLRequest, token: CancellationToken?, progress: ProgressHandler?, completion: @escaping (Nuke.Result<(Data, URLResponse)>) -> Void) {
        // Alamofire.SessionManager automatically starts requests as soon as they are created (see `startRequestsImmediately`)
        let task = manager.request(request)
            .validate()
            .downloadProgress(closure: { progress?($0.completedUnitCount, $0.totalUnitCount) })
            .response(completionHandler: { (response) in
                if let data = response.data, let response: URLResponse = response.response {
                    completion(.success((data, response)))
                } else {
                    completion(.failure(response.error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)))
                }
            })
        token?.register { task.cancel() }
    }
}
```

That's it. You can now create a `Nuke.Manager` instance with your custom data loader and use it to load images:

```swift
let loader = Nuke.Loader(loader: AlamofireDataLoader())
let manager = Nuke.Manager(loader: loader, cache: Cache.shared)

manager.loadImage(with: url, into: imageView)
```

### Using Other Caching Libraries

By default, Nuke uses a `Foundation.URLCache` which is a part of Foundation URL Loading System. However sometimes built-in cache might not be performant enough, or might not fit your needs.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) to learn more about URLCache, HTTP caching, and more

> See [Performance Guide: On-Disk Caching](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md#on-disk-caching) for more info

Nuke can be used with any third party caching library.

1) Add conformance to `DataCaching` protocol:

```swift
extension DFCache: DataCaching {
    public func cachedData(for key: String) -> Data? {
        return self.cachedData(forKey: key)
    }

    public func storeData(_ data: Data, for key: String) {
        self.store(data, forKey: key)
    }
}
```

2) Configure `Nuke.Manager` to use a new `DFCache`:

```swift
ImagePipeline.shared = ImagePipeline {
    let conf = URLSessionConfiguration.default
    conf.urlCache = nil // Disable native URLCache
    $0.dataLoader = DataLoader(configuration: conf)

    $0.dataCache = DFCache(name: "com.github.kean.Nuke.DFCache", memoryCache: nil)
}
```
