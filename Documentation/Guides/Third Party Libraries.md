### Using Other Caching Libraries

By default Nuke uses a `Foundation.URLCache` which is a part of Foundation URL Loading System. However sometimes built-in cache might not be performant enough, or might not fit your needs.

> See [Image Caching Guide](https://kean.github.io/blog/image-caching) to learn more about URLCache, HTTP caching, and more

> See [Performance Guide: On-Disk Caching](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Performance%20Guide.md#on-disk-caching) for more info

Nuke can be used with a third party caching libraries. I'm going to use [DFCache](https://github.com/kean/DFCache) as an example, however any caching library with a similar APIs can be used instead. Here are the step to configure Nuke to use DFCache:

1. Create a custom CachingDataLoader that uses `Nuke.DataLoader` for networking, but checks `DFCache` before starting a network request:

```swift
import Nuke
import DFCache

class CachingDataLoader: DataLoading {
    private let loader: DataLoading
    private let cache: DFCache
    private let scheduler: Scheduler

    public init(loader: DataLoading, cache: DFCache, scheduler: Scheduler = DispatchQueueScheduler(queue: DispatchQueue(label: "com.github.kean.Nuke.CachingDataLoader"))) {
        self.loader = loader
        self.cache = cache
        self.scheduler = scheduler
    }

    public func loadData(with request: Request, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
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

2. Configure `Nuke.Manager` to use a new `CachingDataLoader`:

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
