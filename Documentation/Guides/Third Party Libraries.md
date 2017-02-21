### Using Other Networking Libraries

By default, Nuke uses a `Foundation.URLSession` for all the networking. Apps may have their own network layer they may wish to use instead.

Nuke already has an [Alamofire plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that allows you to load image data using [Alamofire.SessionManager](https://github.com/Alamofire/Alamofire).  If you want to use Nuke with Alamofire simply follow the plugin's docs.

If you'd like to use some other networking library or use your own custom code all you need to do is implement `Nuke.DataLoading` protocol which consists of a single method:

```swift
/// Loads data.
public protocol DataLoading {
    /// Loads data with the given request.
    func loadData(with request: Request,
                  token: CancellationToken?,
                  completion: @escaping (Result<(Data, URLResponse)>) -> Void)
}
```

You can use [Alamofire plugin](https://github.com/kean/Nuke-Alamofire-Plugin) as a starting point. Here's its slightly simplified implementation:

```swift
import Alamofire
import Nuke

class AlamofireDataLoader: Nuke.DataLoading {
    private let manager: Alamofire.SessionManager

    init(manager: Alamofire.SessionManager = Alamofire.SessionManager.default) {
        self.manager = manager
    }

    // MARK: Nuke.DataLoading

    func loadData(with request: Nuke.Request, token: CancellationToken?, completion: @escaping (Nuke.Result<(Data, URLResponse)>) -> Void) {
        // Alamofire.SessionManager automatically starts requests as soon as they are created (see `startRequestsImmediately`)
        let task = self.manager.request(request.urlRequest).response(completionHandler: { (response) in
            if let data = response.data, let response: URLResponse = response.response {
                completion(.success((data, response)))
            } else {
                completion(.failure(response.error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)))
            }
        })
        token?.register {
            task.cancel() // gets called when the token gets cancelled
        }
    }
}
```

That's it. You can now create a `Nuke.Manager` instance with your custom data loader and use it to load images:

```swift
let loader = Nuke.Loader(loader: AlamofireDataLoader())
let manager = Nuke.Manager(loader: loader, cache: Cache.shared)

manager.loadImage(with: url, into: imageView)
```

There is one more thing that you may want to consider. Your networking layers might not provide a built-in way to set a hard limit on a maximum number of concurrent requests. In case you do want to add such limit you can use a *Scheduling* infrastructure provided by Nuke, namely `Nuke.OperationQueueScheduler` class:

```swift
private let scheduler = Nuke.OperationQueueScheduler(maxConcurrentOperationCount: 6)

/// Loads data using Alamofire.SessionManager.
public func loadData(with request: Nuke.Request, token: CancellationToken?, completion: @escaping (Nuke.Result<(Data, URLResponse)>) -> Void) {
    scheduler.execute(token: token) { finish in
        // Alamofire.SessionManager automatically starts requests as soon as they are created (see `startRequestsImmediately`)
        let task = self.manager.request(request.urlRequest).response(completionHandler: { (response) in
            if let data = response.data, let response: URLResponse = response.response {
                completion(.success((data, response)))
            } else {
                completion(.failure(response.error ?? NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown, userInfo: nil)))
            }
            finish() // finish an underlying concurrent Foundation.Operation
        })
        token?.register {
            task.cancel()
            finish()
        }
    }
}
```

### Using Other Caching Libraries

By default, Nuke uses a `Foundation.URLCache` which is a part of Foundation URL Loading System. However sometimes built-in cache might not be performant enough, or might not fit your needs.

> See [Image Caching Guide](https://kean.github.io/blog/image-caching) to learn more about URLCache, HTTP caching, and more

> See [Performance Guide: On-Disk Caching](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md#on-disk-caching) for more info

Nuke can be used with a third party caching library. I'm going to use [DFCache](https://github.com/kean/DFCache) as an example, however any caching library with a similar APIs can be used instead. Here are the steps to configure Nuke to use DFCache:

1) Create a custom CachingDataLoader that uses `Nuke.DataLoader` for networking, but checks `DFCache` before starting a network request:

```swift
import Nuke
import DFCache

class CachingDataLoader: DataLoading {
    private let loader: DataLoading
    private let cache: DFCache
    private let scheduler: Scheduler

    init(loader: DataLoading, cache: DFCache, scheduler: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.github.kean.Nuke.CachingDataLoader"))) {
        self.loader = loader
        self.cache = cache
        self.scheduler = scheduler
    }

    func loadData(with request: Request, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
        guard let key = makeCacheKey(for: request) else {
            loader.loadData(with: request, token: token, completion: completion)
            return
        }
        scheduler.execute(token: token) { [weak self] in
            if let response = self?.cache.cachedObject(forKey: key) as? CachedURLResponse {
                completion(.success((response.data, response.response)))
            } else {
                self?.loader.loadData(with: request, token: token) {
                    if let val = $0.value {
                        self?.cache.store(CachedURLResponse(response: val.1, data: val.0), forKey: key)
                    }
                    completion($0)
                }

            }
        }
    }

    private func makeCacheKey(for request: Request) -> String? {
        return request.urlRequest.url?.absoluteString
    }
}
```

2) Configure `Nuke.Manager` to use a new `CachingDataLoader`:

```swift
// Create DFCache instance. It makes sense not to store data in memory cache:
let cache = DFCache(name: "com.github.kean.Nuke.CachingDataLoader", memoryCache: nil)

// Create our custom CachingDataLoader:
let dataLoader = CachingDataLoader(loader: Nuke.DataLoader(), cache: cache)

// Create Manager which would utilize our data loader as a part of its
// image loading pipeline:
let manager = Nuke.Manager(loader: Nuke.Loader(loader: dataLoader), cache: Nuke.Cache.shared)

// Use newly created manager:
manager.loadImage(with: <#request#>, into: <#T##Target#>)
```
