// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadData` calls.
final class TaskLoadData: AsyncPipelineTask<ImageResponse>, JobSubscriber {
    override func start() {
        if let data = pipeline.cache.cachedData(for: request) {
            let container = ImageContainer(image: .init(), data: data)
            let response = ImageResponse(container: container, request: request)
            self.send(value: response, isCompleted: true)
        } else {
            self.loadData()
        }
    }

    private func loadData() {
        guard !request.options.contains(.returnCacheDataDontLoad) else {
            return send(error: .dataMissingInCache)
        }
        let request = request.withProcessors([])
        dependency = pipeline.makeTaskFetchOriginalData(for: request).subscribe(self)
    }

    // TODO: add default parsing for value
    func receive(_ event: Job<(Data, URLResponse?)>.Event) {
        switch event {
        case let .value((data, urlResponse), isCompleted):
            let container = ImageContainer(image: .init(), data: data)
            let response = ImageResponse(container: container, request: request, urlResponse: urlResponse)
            if isCompleted {
                send(value: response, isCompleted: isCompleted)
                storeDataInCacheIfNeeded(data)
            }
        case .progress(let progress):
            send(progress: progress)
        case .error(let error):
            send(error: error)
        }
    }
}
