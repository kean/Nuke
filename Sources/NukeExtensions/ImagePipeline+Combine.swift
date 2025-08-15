// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Combine
import Foundation
import Nuke

extension ImagePipeline {
    /// Returns a publisher which starts a new ``ImageTask`` when a subscriber is added.
    public nonisolated func imagePublisher(with url: URL) -> AnyPublisher<ImageResponse, ImageTask.Error> {
        imagePublisher(with: ImageRequest(url: url))
    }

    /// Returns a publisher which starts a new ``ImageTask`` when a subscriber is added.
    public nonisolated func imagePublisher(with request: ImageRequest) -> AnyPublisher<ImageResponse, ImageTask.Error> {
        ImagePublisher(request: request, pipeline: self).eraseToAnyPublisher()
    }
}

/// A publisher that starts a new `ImageTask` when a subscriber is added.
///
/// If the requested image is available in the memory cache, the value is
/// delivered immediately. When the subscription is cancelled, the task also
/// gets cancelled.
///
/// - note: In case the pipeline has `isProgressiveDecodingEnabled` option enabled
/// and the image being downloaded supports progressive decoding, the publisher
/// might emit more than a single value.
struct ImagePublisher: Publisher, Sendable {
    typealias Output = ImageResponse
    typealias Failure = ImageTask.Error

    let request: ImageRequest
    let pipeline: ImagePipeline

    func receive<S>(subscriber: S) where S: Subscriber, S: Sendable, Failure == S.Failure, Output == S.Input {
        let subscription = ImageSubscription(
            request: self.request,
            pipeline: self.pipeline,
            subscriber: subscriber
        )
        subscriber.receive(subscription: subscription)
    }
}

private final class ImageSubscription<S>: Subscription where S: Subscriber, S: Sendable, S.Input == ImageResponse, S.Failure == ImageTask.Error {
    private var task: ImageTask?
    private let subscriber: S?
    private let request: ImageRequest
    private let pipeline: ImagePipeline
    private var isStarted = false

    init(request: ImageRequest, pipeline: ImagePipeline, subscriber: S) {
        self.pipeline = pipeline
        self.request = request
        self.subscriber = subscriber

    }

    func request(_ demand: Subscribers.Demand) {
        guard demand > 0 else { return }
        guard let subscriber else { return }

        if let image = pipeline.cache[request] {
            _ = subscriber.receive(ImageResponse(container: image, request: request, cacheType: .memory))

            if !image.isPreview {
                subscriber.receive(completion: .finished)
                return
            }
        }

        task = pipeline.loadImage(
             with: request,
             progress: { response, _, _ in
                 if let response {
                    // Send progressively decoded image (if enabled and if any)
                     _ = subscriber.receive(response)
                 }
             },
             completion: { result in
                 switch result {
                 case let .success(response):
                    _ = subscriber.receive(response)
                    subscriber.receive(completion: .finished)
                 case let .failure(error):
                     subscriber.receive(completion: .failure(error))
                 }
             }
         )
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
