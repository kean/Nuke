// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadData` calls.
final class TaskLoadData: ImagePipelineTask<(Data, URLResponse?)> {
    override func start() {
        guard let dataCache = pipeline.configuration.dataCache,
              request.cachePolicy != .reloadIgnoringCachedData else {
            loadData()
            return
        }
        operation = pipeline.configuration.dataCachingQueue.add { [weak self] in
            self?.getCachedData(dataCache: dataCache)
        }
    }

    private func getCachedData(dataCache: DataCaching) {
        let data = signpost(log, "ReadCachedImageData") {
            pipeline.cache.cachedData(for: request)
        }
        async {
            if let data = data {
                self.send(value: (data, nil), isCompleted: true)
            } else {
                self.loadData()
            }
        }
    }

    private func loadData() {
        guard request.cachePolicy != .returnCacheDataDontLoad else {
            // Same error that URLSession produces when .returnCacheDataDontLoad is specified and the
            // data is no found in the cache.
            let error = NSError(domain: URLError.errorDomain, code: URLError.resourceUnavailable.rawValue, userInfo: nil)
            return send(error: .dataLoadingFailed(error))
        }

        dependency = pipeline.makeTaskFetchOriginalImageData(for: request).subscribe(self) { [weak self] in
            self?.didReceiveData($0.0, urlResponse: $0.1, isCompleted: $1)
        }
    }

    private func didReceiveData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool) {
        // Sanity check, should never happen in practice
        guard !data.isEmpty else {
            send(error: .dataLoadingFailed(URLError(.unknown, userInfo: [:])))
            return
        }

        send(value: (data, urlResponse), isCompleted: isCompleted)
    }
}
