// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    /// A delegate that allows you to customize the pipeline dynamically on a per-request basis.
    ///
    /// The isolation of every method is declared in its signature. The methods that
    /// ask the delegate for a customization – the factories, the cache key, the
    /// policies, and the decompression – are `nonisolated`, so the pipeline can call
    /// them from whichever context needs the answer, including the synchronous
    /// ``ImagePipeline/Cache-swift.struct`` API. The methods that report to the
    /// delegate run on ``ImagePipelineActor``, where a delegate can keep state
    /// without a lock. ``Delegate/imageTaskCreated(_:pipeline:)`` is the exception:
    /// it is called immediately, in the context that created the task.
    ///
    /// - important: Every method has a default implementation, so a method with
    /// the wrong signature compiles, and the pipeline never calls it. Declare
    /// the conformance in an extension, where the compiler warns about a method
    /// that nearly matches a requirement. It doesn't warn about a method with
    /// a different number of parameters, so check those against the signatures
    /// here.
    public protocol Delegate: AnyObject, Sendable {
        // MARK: Misc

        /// Returns image decoder for the given context.
        nonisolated func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)?

        /// Returns image encoder for the given context.
        nonisolated func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> any ImageEncoding

        /// Returns the preview policy for progressive decoding of the given request.
        nonisolated func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy

        // MARK: Data Loading

        /// Returns data loader for the given request.
        nonisolated func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading

        /// Intercepts the URL request just before data loading begins, allowing
        /// you to modify or replace it.
        ///
        /// Use this hook to inject authentication tokens, sign requests, or
        /// perform any other async pre-flight work. Throw to cancel the request
        /// with a meaningful error — for example, when a token refresh fails.
        ///
        /// The default implementation returns `urlRequest` unchanged.
        ///
        /// The pipeline calls it again for every retry, with the original URL
        /// request, so a retry goes out with the current token.
        ///
        /// - important: Not called for requests using a custom data fetch closure
        ///   or for local file resources.
        /// - parameters:
        ///   - request: The image request being loaded.
        ///   - urlRequest: The URL request that is about to be sent.
        ///   - pipeline: The pipeline performing the request.
        /// - returns: The URL request to use for loading. Return `urlRequest`
        ///   unchanged to proceed without modification.
        /// - throws: If an error is thrown, the image request fails with
        ///   ``ImagePipeline/Error/dataLoadingFailed(error:)`` wrapping the error.
        @ImagePipelineActor
        func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest

        /// Decides what to do after an attempt to load an image fails. The
        /// pipeline asks once per failed attempt, whatever the number of
        /// requests that share the load.
        ///
        /// Use this hook for what a ``RetryPolicy`` can't express. It can
        /// suspend, so it can also fix what went wrong. A request that follows
        /// goes through ``willLoadData(for:urlRequest:pipeline:)``, which
        /// is where a refreshed token gets into it:
        ///
        /// ```swift
        /// func retryDecision(for context: ImagePipeline.RetryContext, pipeline: ImagePipeline) async -> ImagePipeline.RetryDecision {
        ///     if context.statusCode == 401, context.retryCount == 0 {
        ///         await session.refreshToken()
        ///         return .retry(after: 0)
        ///     }
        ///     return context.policy?.decision(for: context) ?? .stop
        /// }
        /// ```
        ///
        /// The default implementation does what the ``RetryContext/policy``
        /// says, and stops if there is none.
        ///
        /// - important: The delegate has the last word, so ``RetryPolicy/maxRetryCount``
        ///   doesn't limit a decision made here. Check ``RetryContext/retryCount``.
        ///
        /// - note: Not called for a local resource, or for a request that
        ///   ``willLoadData(for:urlRequest:pipeline:)`` rejects by throwing. A
        ///   failure to decode or process an image isn't a failed attempt: the
        ///   same data would fail again.
        /// - parameters:
        ///   - context: The failed attempt.
        ///   - pipeline: The pipeline performing the request.
        /// - returns: What the pipeline should do next.
        @ImagePipelineActor
        func retryDecision(for context: ImagePipeline.RetryContext, pipeline: ImagePipeline) async -> ImagePipeline.RetryDecision

        // MARK: Caching

        /// Returns in-memory image cache for the given request. Return `nil` to prevent cache reads and writes.
        nonisolated func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)?

        /// Returns disk cache for the given request. Return `nil` to prevent cache
        /// reads and writes.
        nonisolated func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)?

        /// Returns a cache key identifying the image produced for the given request
        /// (including image processors). The key is used for both in-memory and
        /// on-disk caches.
        ///
        /// Return `nil` to use a default key.
        nonisolated func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String?

        /// Gets called when the pipeline is about to save data for the given request.
        ///
        /// This method is called only if the request parameters and data caching policy
        /// of the pipeline already allow caching.
        ///
        /// The default implementation returns `data` unchanged.
        ///
        /// - parameters:
        ///   - data: Either the original data or the encoded image in case of storing
        ///   a processed or re-encoded image.
        ///   - image: Non-nil in case storing an encoded image.
        ///   - request: The request for which image is being stored.
        ///   - pipeline: The pipeline that is about to store the data.
        /// - returns: The data to store. Return `nil` or empty data to prevent caching.
        @ImagePipelineActor
        func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data?

        // MARK: Decompression

        /// Returns `true` if the pipeline should decompress the given response.
        nonisolated func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool

        /// Decompresses the given image response.
        ///
        /// Called on a background queue managed by the pipeline.
        nonisolated func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse

        // MARK: ImageTask

        /// Gets called when the task is created. Unlike the other task events, it
        /// is called immediately, in the context that created the task.
        nonisolated func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline)

        /// Gets called when the task is started by the pipeline.
        @ImagePipelineActor
        func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline)

        /// Gets called when the task receives an event.
        @ImagePipelineActor
        func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline)
    }
}

extension ImagePipeline.Delegate {
    public func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)? {
        pipeline.configuration.imageCache
    }

    public func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
        pipeline.configuration.dataLoader
    }

    @ImagePipelineActor
    public func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        urlRequest
    }

    @ImagePipelineActor
    public func retryDecision(for context: ImagePipeline.RetryContext, pipeline: ImagePipeline) async -> ImagePipeline.RetryDecision {
        context.policy?.decision(for: context) ?? .stop
    }

    public func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)? {
        pipeline.configuration.dataCache
    }

    public func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        pipeline.configuration.makeImageDecoder(context)
    }

    public func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> any ImageEncoding {
        pipeline.configuration.makeImageEncoder(context)
    }

    public func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy {
        ImagePipeline.PreviewPolicy.default(for: context.data)
    }

    public func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? {
        nil
    }

    @ImagePipelineActor
    public func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        data
    }

    public func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
        pipeline.configuration.isDecompressionEnabled
    }

    public func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse {
        var response = response
        response.container.image = ImageDecompression.decompress(image: response.image, isUsingPrepareForDisplay: pipeline.configuration.isUsingPrepareForDisplay)
        return response
    }

    public func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {}

    @ImagePipelineActor
    public func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {}

    @ImagePipelineActor
    public func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {}
}

/// The pipeline invokes the delegate hooks through these methods: they skip the
/// hooks entirely when the pipeline is created without a custom delegate.
extension ImagePipeline {
    @ImagePipelineActor
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest) async throws -> URLRequest {
        guard !isDefaultDelegate else { return urlRequest }
        return try await delegate.willLoadData(for: request, urlRequest: urlRequest, pipeline: self)
    }

    @ImagePipelineActor
    func retryDecision(for context: RetryContext) async -> RetryDecision {
        guard !isDefaultDelegate else {
            return context.policy?.decision(for: context) ?? .stop
        }
        return await delegate.retryDecision(for: context, pipeline: self)
    }

    /// Returns `nil` if the data must not be stored, including when the delegate
    /// returns empty data.
    @ImagePipelineActor
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest) async -> Data? {
        guard !isDefaultDelegate else { return data }
        let data = await delegate.willCache(data: data, image: image, for: request, pipeline: self)
        return (data?.isEmpty ?? true) ? nil : data
    }

    nonisolated func imageTaskCreated(_ task: ImageTask, isDataTask: Bool) {
        guard !isDataTask && !isDefaultDelegate else { return }
        delegate.imageTaskCreated(task, pipeline: self)
    }

    func imageTaskDidStart(_ task: ImageTask, isDataTask: Bool) {
        guard !isDataTask && !isDefaultDelegate else { return }
        delegate.imageTaskDidStart(task, pipeline: self)
    }

    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, isDataTask: Bool) {
        guard !isDataTask && !isDefaultDelegate else { return }
        delegate.imageTask(task, didReceiveEvent: event, pipeline: self)
    }
}

final class ImagePipelineDefaultDelegate: ImagePipeline.Delegate {}
