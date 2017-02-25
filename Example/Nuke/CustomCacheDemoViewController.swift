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

        // Create custom CachingDataLoader
        // Disable disk caching built into URLSession
        let conf = URLSessionConfiguration.default
        conf.urlCache = nil
        
        let dataLoader = CachingDataLoader(loader: Nuke.DataLoader(configuration: conf), cache: cache)

        // Create Manager which would utilize our data loader as a part of its
        // image loading pipeline
        manager = Manager(loader: Nuke.Loader(loader: dataLoader), cache: Nuke.Cache.shared)
    }
}


protocol DataCaching {
    func cachedResponse(for request: URLRequest) -> CachedURLResponse?
    func storeResponse(_ response: CachedURLResponse, for request: URLRequest)
}

class CachingDataLoader: DataLoading {
    private let loader: DataLoading
    private let cache: DataCaching
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.CachingDataLoader")

    public init(loader: DataLoading, cache: DataCaching) {
        self.loader = loader
        self.cache = cache
    }

    public func loadData(with request: Request, token: CancellationToken?, completion: @escaping (Result<(Data, URLResponse)>) -> Void) {
        queue.async { [weak self] in
            if token?.isCancelling == true {
                return
            }
            let urlRequest = request.urlRequest
            if let response = self?.cache.cachedResponse(for: urlRequest) {
                completion(.success((response.data, response.response)))
            } else {
                self?.loader.loadData(with: request, token: token) {
                    $0.value.map { self?.store($0, for: urlRequest) }
                    completion($0)
                }
            }
        }
    }

    private func store(_ val: (Data, URLResponse), for request: URLRequest) {
        queue.async { [weak self] in
            self?.cache.storeResponse(CachedURLResponse(response: val.1, data: val.0), for: request)
        }
    }
}

extension DFCache: DataCaching {
    func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        return key(for: request).map(cachedObject) as? CachedURLResponse
    }
    
    func storeResponse(_ response: CachedURLResponse, for request: URLRequest) {
        key(for: request).map { store(response, forKey: $0) }
    }
    
    private func key(for request: URLRequest) -> String? {
        return request.url?.absoluteString
    }
}
