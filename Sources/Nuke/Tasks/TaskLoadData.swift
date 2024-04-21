// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadData` calls.
final class TaskLoadData: ImagePipelineTask<(Data, URLResponse?)> {
    override func start() {
        if let data = pipeline.cache.cachedData(for: request) {
            self.send(value: (data, nil), isCompleted: true)
        } else {
            self.loadData()
        }
    }

    private func loadData() {
        guard !request.options.contains(.returnCacheDataDontLoad) else {
            return send(error: .dataMissingInCache)
        }

        let request = self.request.withProcessors([])
        dependency = pipeline.makeTaskFetchOriginalData(for: request).subscribe(self) { [weak self] in
            self?.didReceiveData($0.0, urlResponse: $0.1, isCompleted: $1)
        }
    }

    private func didReceiveData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool) {
        send(value: (data, urlResponse), isCompleted: isCompleted)
    }
}
