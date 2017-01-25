// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import DFCache

class CustomCacheDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let dataLoader = CachingDataLoader(loader: Nuke.DataLoader(), cache: DFCache(name: "test", memoryCache: nil))
        manager = Manager(loader: Nuke.Loader(loader: dataLoader), cache: Nuke.Cache.shared)
    }
}


class CachingDataLoader: DataLoading {
    private var loader: DataLoading
    private var cache: DFCache

    public init(loader: DataLoading, cache: DFCache) {
        self.loader = loader
        self.cache = cache
    }

    public func loadData(with request: URLRequest, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
        if let token = token, token.isCancelling { return }
        guard let cacheKey = request.url?.absoluteString else { // can't consruct key
            loader.loadData(with: request, token: token, completion: completion)
            return
        }
        cache.cachedObject(forKey: cacheKey) { [weak self] in
            if let response = $0 as? CachedURLResponse {
                completion(.success((response.data, response.response)))
            } else {
                self?.loader.loadData(with: request, token: token) {
                    if let val = $0.value {
                        self?.cache.store(CachedURLResponse(response: val.1, data: val.0), forKey: cacheKey)
                    }
                    completion($0)
                }
            }
        }
    }
}
