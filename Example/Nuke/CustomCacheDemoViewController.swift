// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import DFCache

class CustomCacheDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Create DFCache instance. It makes sense not to store data in memory cache.
        let cache = DFCache(name: "com.github.kean.Nuke.CachingDataLoader", memoryCache: nil)

        // Create our custom CachingDataLoader
        let dataLoader = CachingDataLoader(loader: Nuke.DataLoader(), cache: cache)

        // Create Manager which would utilize our data loader as a part of its
        // image loading pipeline
        manager = Manager(loader: Nuke.Loader(loader: dataLoader), cache: Nuke.Cache.shared)
    }
}


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
