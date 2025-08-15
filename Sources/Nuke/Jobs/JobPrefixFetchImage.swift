// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

// TODO: can we run the preflight task without creating a Job (expensive?)
// TODO: can we create a chain of tasks without `start()`?

/// A non-coalesced task that represents the initial (quick) part of the work.
final class JobPrefixFetchImage: AsyncPipelineTask<ImageResponse>, JobSubscriber {
    override func start() {
        if let container = pipeline.cache[request] {
            let response = ImageResponse(container: container, request: request, cacheType: .memory)
            send(value: response, isCompleted: !container.isPreview)
            if !container.isPreview {
                return // The final image is loaded
            }
        }
        // TODO: check original image cache also!
        if let data = pipeline.cache.cachedData(for: request) {
            decodeCachedData(data)
        } else {
            fetchImage()
        }
    }

    // MARK: Disk Cache

    private func decodeCachedData(_ data: Data) {
        let context = ImageDecodingContext(request: request, data: data, cacheType: .disk)
        guard let decoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline) else {
            return didFinishDecoding(with: nil)
        }
        // TODO: this doesn't check if decompression needed or not
        decode(context, decoder: decoder) { [weak self] result in
            self?.didFinishDecoding(with: try? result.get())
        }
    }

    private func didFinishDecoding(with response: ImageResponse?) {
        if let response {
            decompress(response) {
                self.didReceiveResponse($0)
            }
        } else {
            fetchImage()
        }
    }

    // MARK: Fetch Image

    private func fetchImage() {
        guard !request.options.contains(.returnCacheDataDontLoad) else {
            return send(error: .dataMissingInCache)
        }
        // TODO: can we do the preflight task here with no processors? or should the initial task do this?
        dependency = pipeline.makeJobFetchImage(for: request).subscribe(self)
    }

    func receive(_ event: Job<ImageResponse>.Event) {
        switch event {
        case let .value(value, _):
            didReceiveResponse(value)
        case .progress(let progress):
            send(progress: progress)
        case .error(let error):
            send(error: error)
        }
    }

    // MARK: Finish

    // TODO: cleanup how this is used
    private func didReceiveResponse(_ response: ImageResponse) {
        storeImageInCaches(response)
        send(value: response, isCompleted: !response.isPreview)
    }
}
