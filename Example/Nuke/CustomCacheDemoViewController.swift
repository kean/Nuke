// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke
import DFCache

final class CustomCacheDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Create a pipleine which would utilize our data loader as a part of its
        // image loading pipeline
        pipeline = ImagePipeline {
            // Create DFCache instance. It makes sense not to store data in memory cache.
            let cache = DFCache(name: "com.github.kean.Nuke.CachingDataLoader", memoryCache: nil)

            // Create custom CachingDataLoader
            // Disable disk caching built into URLSession
            let conf = URLSessionConfiguration.default
            conf.urlCache = nil

            $0.dataLoader = CachingDataLoader(loader: DataLoader(configuration: conf), cache: cache)
        }
    }
}

protocol DataCaching {
    func cachedResponse(for request: URLRequest) -> CachedURLResponse?
    func storeResponse(_ response: CachedURLResponse, for request: URLRequest)
}

final class CachingDataLoader: DataLoading {
    private let loader: DataLoading
    private let cache: DataCaching
    private let queue = DispatchQueue(label: "com.github.kean.Nuke.CachingDataLoader")

    private final class _Task: Cancellable {
        weak var loader: CachingDataLoader?
        var data = [Data]()
        var response: URLResponse?
        var isCancelled = false
        weak var dataLoadingTask: Cancellable?

        func cancel() {
            loader?._cancel(self)
        }
    }

    public init(loader: DataLoading, cache: DataCaching) {
        self.loader = loader
        self.cache = cache
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        let task = _Task()
        task.loader = self

        queue.async { [weak self] in
            guard !task.isCancelled else { return }

            if let response = self?.cache.cachedResponse(for: request) {
                didReceiveData(response.data, response.response)
                completion(nil)
            } else {
                task.dataLoadingTask = self?.loader.loadData(
                    with: request,
                    didReceiveData: { (data, response) in
                        self?.queue.async {
                            task.data.append(data) // store received data
                            task.response = response
                            didReceiveData(data, response) // proxy call
                        }
                }, completion: { (error) in
                    self?.queue.async {
                        if error == nil {
                            self?._storeResponse(for: task, request: request)
                        }
                        completion(error) // proxy call
                    }
                })
            }
        }

        return task
    }

    private func _cancel(_ task: _Task) {
        queue.async {
            guard !task.isCancelled else { return }
            task.isCancelled = true
            task.dataLoadingTask?.cancel()
            task.dataLoadingTask = nil
        }
    }

    private func _storeResponse(for task: _Task, request: URLRequest) {
        guard let response = task.response, !task.data.isEmpty else { return }
        var buffer = Data()
        task.data.forEach { buffer.append($0) }
        task.data.removeAll()
        cache.storeResponse(CachedURLResponse(response: response, data: buffer), for: request)
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
