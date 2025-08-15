// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

// TODO: rename/remove
// Each task holds a strong reference to the pipeline. This is by design. The
// user does not need to hold a strong reference to the pipeline.
class AsyncPipelineTask<Value: Sendable>: Job<Value> {
    let pipeline: ImagePipeline
    // A canonical request representing the unit work performed by the task.
    let request: ImageRequest

    init(_ pipeline: ImagePipeline, _ request: ImageRequest) {
        self.pipeline = pipeline
        self.request = request
        
        super.init()
    }
}

// MARK: - AsyncPipelineTask (Helpers)

extension AsyncPipelineTask {
    func decode(_ context: ImageDecodingContext, decoder: any ImageDecoding, _ completion: @ImagePipelineActor @Sendable @escaping (Result<ImageResponse, ImageTask.Error>) -> Void) {
        let operation = Operation(name: "DecodeImage") {
            decoder.decode(context)
        }
        if decoder.isAsynchronous {
            operation.queue = pipeline.configuration.imageDecodingQueue
        }
        self.operation = operation.receive(self, completion)
    }

    func decompress(_ response: ImageResponse, _ completion: @ImagePipelineActor @Sendable @escaping (ImageResponse) -> Void) {
        let operation = Operation(name: "DecompressImage") {
            let value = self.pipeline.delegate.decompress(response: response, request: self.request, pipeline: self.pipeline)
            return .success(value)
        }
        operation.queue = pipeline.configuration.imageDecompressingQueue
        self.operation = operation.receive(self) {
            switch $0 {
            case let .success(value): completion(value)
            case .failure: completion(response)
            }
        }
    }

    func process(_ context: ImageProcessingContext, response: ImageResponse, processors: [any ImageProcessing], _ completion: @ImagePipelineActor @Sendable @escaping (Result<ImageResponse, ImageTask.Error>) -> Void) {
        let operation = Operation<ImageResponse>(name: "ProcessImage") {
            var response = response
            for processor in processors {
                do {
                    response.container = try processor.process(response.container, context: context)
                } catch {
                    return .failure(.processingFailed(processor: processor, context: context, error: error))
                }
            }
            return .success(response)
        }
        operation.queue = pipeline.configuration.imageProcessingQueue
        self.operation = operation.receive(self, completion)
    }

    func storeImageInCaches(_ response: ImageResponse) {
        pipeline.cache[request] = response.container
        if shouldStoreResponseInDataCache(response) {
            storeImageInDataCache(response)
        }
    }

    private func storeImageInDataCache(_ response: ImageResponse) {
        guard let dataCache = pipeline.delegate.dataCache(for: request, pipeline: pipeline) else {
            return
        }
        let context = ImageEncodingContext(request: request, image: response.image, urlResponse: response.urlResponse)
        let encoder = pipeline.delegate.imageEncoder(for: context, pipeline: pipeline)
        let key = pipeline.cache.makeDataCacheKey(for: request)

        let operation = Operation<Void>(name: "EncodeImage") {
            let encodedData = encoder.encode(response.container, context: context)
            if let data = encodedData, !data.isEmpty {
                self.pipeline.delegate.willCache(data: data, image: response.container, for: self.request, pipeline: self.pipeline) {
                    guard let data = $0, !data.isEmpty else { return }
                    // Important! Storing directly ignoring `ImageRequest.Options`.
                    dataCache.storeData(data, for: key) // This is instant, writes are async
                }
            }
            return .success(())
        }
        if !pipeline.configuration.debugIsSyncImageEncoding {
            operation.queue = pipeline.configuration.imageEncodingQueue
        }
        operation.receive { _ in } // Adding a subscriber starts a job
    }

    private func shouldStoreResponseInDataCache(_ response: ImageResponse) -> Bool {
        guard !response.container.isPreview,
              !(response.cacheType == .disk),
              !(request.url?.isLocalResource ?? false) else {
            return false
        }
        let isProcessed = !request.processors.isEmpty || request.thumbnail != nil
        switch pipeline.configuration.dataCachePolicy {
        case .automatic:
            return isProcessed
        case .storeOriginalData:
            return false
        case .storeEncodedImages:
            return true
        case .storeAll:
            return isProcessed
        }
    }
}
