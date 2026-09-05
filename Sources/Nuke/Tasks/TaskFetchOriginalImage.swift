// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Receives data from ``TaskLoadImageData`` and decodes it as it arrives.
final class TaskFetchOriginalImage: AsyncPipelineTask<ImageResponse> {
    private var decoder: (any ImageDecoding)?
    /// The preview policy the current ``decoder`` was created with. `nil` until
    /// a decoder is created from partial data.
    private var decoderPreviewPolicy: ImagePipeline.PreviewPolicy?
    /// The number of times the preview policy was evaluated and the amount of
    /// data it was last evaluated for.
    private var previewPolicyEvaluationCount = 0
    private var previewPolicyDataCount = 0
    private var lastPreviewTime: CFAbsoluteTime?

    /// The maximum number of times the preview policy is evaluated for a single
    /// download. Together with ``resolvePreviewPolicy(for:)`` requiring the data
    /// to double between the evaluations, it covers a 64x growth of the first
    /// chunk – more than enough for any realistic EXIF/ICC preamble.
    private static let maxPreviewPolicyEvaluationCount = 6

    override func start() {
        if case .image(let fetch) = request.resource {
            loadAsyncImage(fetch)
            return
        }
        dependency = pipeline.makeTaskFetchOriginalData(for: request).subscribe(self) { [weak self] in
            self?.didReceiveData($0.0, urlResponse: $0.1, isCompleted: $1)
        }
    }

    /// Receiving data from `TaskFetchOriginalData`.
    private func didReceiveData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool) {
        guard isCompleted || pipeline.configuration.isProgressiveDecodingEnabled else {
            return
        }

        if !isCompleted && operation != nil {
            return // Back pressure - already decoding another progressive data chunk
        }

        if !isCompleted, let last = lastPreviewTime {
            let interval = pipeline.configuration.progressiveDecodingInterval
            if interval > 0 && CFAbsoluteTimeGetCurrent() - last < interval {
                return
            }
        }

        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decoding tasks
        }

        var decodingContext = ImageDecodingContext(request: request, data: data, isCompleted: isCompleted, urlResponse: urlResponse, isAnimatedImageParsingEnabled: pipeline.configuration.isAnimatedImageParsingEnabled)
        if !isCompleted {
            decodingContext.previewPolicy = resolvePreviewPolicy(for: decodingContext)
        }
        let context = decodingContext
        guard let decoder = getDecoder(for: context) else {
            if isCompleted {
                send(error: .decoderNotRegistered(context: context))
            } else {
                // Try again when more data is downloaded.
            }
            return
        }

        decode(context, decoder: decoder) { [weak self] in
            self?.didFinishDecoding(context: context, result: $0)
        }
    }

    private func didFinishDecoding(context: ImageDecodingContext, result: Result<ImageResponse, ImagePipeline.Error>) {
        switch result {
        case .success(let response):
            if !context.isCompleted {
                lastPreviewTime = CFAbsoluteTimeGetCurrent()
            }
            send(value: response, isCompleted: context.isCompleted)
        case .failure(let error):
            if context.isCompleted {
                send(error: error)
            }
        }
    }

    /// Returns the preview policy for the given partially downloaded data.
    ///
    /// A policy that inspects the data – ``ImagePipeline/PreviewPolicy/default(for:)``
    /// in particular – often can't tell what to do from the first chunk: a
    /// progressive JPEG is only known to be progressive once Image I/O parses
    /// the frame header, which for images with large EXIF/ICC preambles happens
    /// well into the download. The policy is re-evaluated as more data arrives,
    /// but each evaluation parses the data that was downloaded so far, so the
    /// retries are limited: the policy is evaluated at most
    /// ``maxPreviewPolicyEvaluationCount`` times, only while it remains
    /// ``ImagePipeline/PreviewPolicy/disabled`` (nothing was decoded yet), and
    /// only when the amount of data at least doubled – there is little to learn
    /// from re-parsing nearly the same data.
    private func resolvePreviewPolicy(for context: ImageDecodingContext) -> ImagePipeline.PreviewPolicy {
        if let policy = decoderPreviewPolicy {
            guard policy == .disabled,
                  previewPolicyEvaluationCount < Self.maxPreviewPolicyEvaluationCount,
                  context.data.count >= previewPolicyDataCount * 2 else {
                return policy
            }
        }
        previewPolicyEvaluationCount += 1
        previewPolicyDataCount = context.data.count
        return pipeline.delegate.previewPolicy(for: context, pipeline: pipeline)
    }

    // Lazily creates the decoder for the task
    private func getDecoder(for context: ImageDecodingContext) -> (any ImageDecoding)? {
        // Return the existing decoder in case it has already been created. The
        // exception is a decoder created with a `.disabled` preview policy that
        // now resolves to a different one: it produced no previews, so there is
        // no decoding state to lose by replacing it.
        if let decoder, context.isCompleted || context.previewPolicy == decoderPreviewPolicy {
            return decoder
        }
        guard let newDecoder = pipeline.delegate.imageDecoder(for: context, pipeline: pipeline) else {
            return nil // Keep the existing decoder, if any, and try again later
        }
        decoder = newDecoder
        if !context.isCompleted {
            decoderPreviewPolicy = context.previewPolicy
        }
        return newDecoder
    }

    // MARK: Async Image Loading

    private func loadAsyncImage(_ fetch: @Sendable @escaping () async throws -> ImageContainer) {
        operation = pipeline.configuration.dataLoadingQueue.add { [weak self] in
            await self?.performAsyncImageLoad(fetch)
        }
    }

    private func performAsyncImageLoad(_ fetch: @Sendable @escaping () async throws -> ImageContainer) async {
        guard !isDisposed else { return }
        do {
            let container = try await fetch()
            send(value: ImageResponse(container: container, request: request), isCompleted: true)
        } catch {
            send(error: .dataLoadingFailed(error: error))
        }
    }
}
