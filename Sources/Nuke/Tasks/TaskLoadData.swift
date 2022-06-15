// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadData` calls.
final class TaskLoadData: ImagePipelineTask<(Data, URLResponse?)> {
    override func start() {
        guard let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline),
              !request.options.contains(.disableDiskCacheReads) else {
            loadData()
            return
        }
        operation = pipeline.configuration.dataCachingQueue.add { [weak self] in
            self?.getCachedData(dataCache: dataCache)
        }
    }

    private func getCachedData(dataCache: any DataCaching) {
        let data = signpost("ReadCachedImageData") {
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
        guard !request.options.contains(.returnCacheDataDontLoad) else {
            return send(error: .dataMissingInCache)
        }

        let request = self.request.withProcessors([])
        dependency = pipeline.makeTaskFetchOriginalImageData(for: request).subscribe(self) { [weak self] in
            self?.didReceiveData($0.0, urlResponse: $0.1, isCompleted: $1)
        }
    }

    private func didReceiveData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool) {
        send(value: (data, urlResponse), isCompleted: isCompleted)
    }
}
