// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Wrapper for tasks created by `loadData` calls.
final class TaskLoadData: AsyncPipelineTask<ImageResponse> {
    override func start() {
        if let data = lookUpCachedData(for: request) ?? lookUpOriginalData() {
            let container = ImageContainer(image: .init(), data: data)
            let response = ImageResponse(container: container, request: request)
            self.send(value: response, isCompleted: true)
        } else {
            self.loadData()
        }
    }

    /// The fetch in `loadData()` stores the original data under the sanitized key.
    private func lookUpOriginalData() -> Data? {
        guard request.thumbnail != nil || !request.processors.isEmpty else {
            return nil
        }
        return lookUpCachedData(for: request.withProcessors([]).withoutThumbnail())
    }

    private func loadData() {
        guard !request.options.contains(.returnCacheDataDontLoad) else {
            return send(error: .dataMissingInCache)
        }
        let request = request.withProcessors([])
        dependency = pipeline.makeTaskFetchOriginalData(for: request).subscribe(self) { [weak self] in
            self?.didReceiveData($0.0, urlResponse: $0.1, isCompleted: $1)
        }
    }

    private func didReceiveData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool) {
        let container = ImageContainer(image: .init(), data: data)
        let response = ImageResponse(container: container, request: request, urlResponse: urlResponse)
        if isCompleted {
            send(value: response, isCompleted: isCompleted)
        }
    }
}
