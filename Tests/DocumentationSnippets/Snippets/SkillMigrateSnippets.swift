// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `skills/nuke-migrate/SKILL.md`, verbatim. Only the `// Nuke 14` half
// of a sample is here: the `// Nuke 13` half doesn't compile, which is the point.

import Foundation
import Nuke
import NukeExtensions
import NukeUI
import SwiftUI

#if canImport(UIKit)
import UIKit

// MARK: Compile errors

final class PosterView: UIView, ImageDisplaying {
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(imageView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func nuke_display(_ container: ImageContainer?) {
        imageView.image = container?.image
    }
}

private func status(of task: ImageTask) {
    let status = task.status
    if status.result == nil, !status.isCancelled {
        print(status.progress.fraction)
    }
}

// MARK: Delegates

private final class PipelineDelegate: Sendable {}

extension PipelineDelegate: ImagePipeline.Delegate {
    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? { nil }
    func imageEncoder(for context: ImageEncodingContext, pipeline: ImagePipeline) -> any ImageEncoding { ImageEncoders.Default() }
    func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy { .default(for: context.data) }
    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading { pipeline.configuration.dataLoader }
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest { urlRequest }
    func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)? { pipeline.configuration.imageCache }
    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)? { pipeline.configuration.dataCache }
    func cacheKey(for request: ImageRequest, pipeline: ImagePipeline) -> String? { nil }
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? { data }
    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool { true }
    func decompress(response: ImageResponse, request: ImageRequest, pipeline: ImagePipeline) -> ImageResponse { response }
    func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {}
    func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {}
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {}
}

private final class PrivacyDelegate: Sendable {
    func shouldStore(_ request: ImageRequest) -> Bool { true }
}

extension PrivacyDelegate: ImagePipeline.Delegate {
    func willCache(data: Data, image: ImageContainer?, for request: ImageRequest, pipeline: ImagePipeline) async -> Data? {
        shouldStore(request) ? data : nil
    }
}

// MARK: LazyImage

private struct BlurredPoster: View {
    let request: ImageRequest
    let isBlurred: Bool
    let isSelected: Bool

    var body: some View {
        LazyImage(request: request)
            .processors(isBlurred ? [ImageProcessors.GaussianBlur()] : [])
            .priority(isSelected ? .high : .normal)
    }
}

// MARK: Animated images

// These are also the samples from the animated section of the migration guide.

private struct AnimatedPoster: View {
    let url: URL

    var body: some View {
        LazyImage(url: url) { state in
            if let container = state.imageContainer, let animation = AnimatedImage(container: container) {
                animation.resizable().scaledToFill()
            } else if let image = state.image {
                image.resizable().scaledToFill()
            }
        }
    }
}

private struct StillPoster: View {
    let url: URL

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            }
        }
    }
}

@MainActor
private func configurePlayback(of lazyImageView: LazyImageView) {
    lazyImageView.imageView.playerOptions.repeatCount = .infinite
    lazyImageView.imageView.isPlaybackEnabled = false
}

private func keepStills() {
    ImagePipeline.shared = ImagePipeline {
        $0.isAnimatedImageParsingEnabled = false
    }
}

@MainActor
private func play(_ response: ImageResponse, in imageView: AnimatedImageView) {
    if let animation = response.container.animation {
        imageView.animatedImage = animation
    }
}

@MainActor
private func playOriginal(url: URL, in imageView: AnimatedImageView) async throws {
    let response = try await ImagePipeline.shared.imageTask(with: ImageRequest(url: url)).response
    if let animation = response.container.animation {
        imageView.animatedImage = animation
    }
}

private func drawDeepImagesInEightBits() {
    ImagePipeline.shared = ImagePipeline {
        $0.isUsingPrepareForDisplay = false
    }
}

// MARK: Errors

private enum PosterError: Error {
    case notFound
}

@MainActor
private final class PosterErrors {
    func show(_ error: PosterError) {}

    func onCompletion(_ result: Result<ImageResponse, ImagePipeline.Error>) {
        if case .failure(.dataLoadingFailed(let underlying)) = result, let error = underlying as? PosterError {
            show(error)
        }
    }
}

// MARK: Defaults

private func restoreSlots() {
    ImagePipeline.shared = ImagePipeline {
        $0.dataLoadingQueue = TaskQueue(maxConcurrentTaskCount: 6, reservedTaskCount: 0)
    }
}

// MARK: NukeExtensions

@MainActor
private func loadIntoView(url: URL?, imageView: UIImageView) {
    let presentation = ImageLoader.Presentation(
        placeholder: UIImage(named: "placeholder"),
        transition: .fadeIn(duration: 0.33),
        failureImage: UIImage(named: "error")
    )
    ImageLoader.load(url, into: imageView, presentation: presentation)
}

#endif
