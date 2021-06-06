// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Combine

/// An observable object that simplifies image loading in SwiftUI.
@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
public final class FetchImage: ObservableObject, Identifiable {
    /// Returns the current fetch result.
    @Published public private(set) var result: Result<ImageResponse, ImagePipeline.Error>?

    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    public var image: PlatformImage? { imageContainer?.image }

    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    @Published public private(set) var imageContainer: ImageContainer?

    /// Returns `true` if the image is being loaded.
    @Published public private(set) var isLoading: Bool = false

    /// The download progress.
    public struct Progress: Equatable {
        /// The number of bytes that the task has received.
        public let completed: Int64

        /// A best-guess upper bound on the number of bytes the client expects to send.
        public let total: Int64
    }

    /// The progress of the image download.
    @Published public private(set) var progress = Progress(completed: 0, total: 0)

    /// Updates the priority of the task, even if the task is already running.
    public var priority: ImageRequest.Priority = .normal {
        didSet { task?.priority = priority }
    }

    /// Gets called when the request is started.
    public var onStart: ((_ task: ImageTask) -> Void)?

    /// Gets called when the request progress is updated.
    public var onProgress: ((_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void)?

    /// Gets called when the requests finished successfully.
    public var onSuccess: ((_ response: ImageResponse) -> Void)?

    /// Gets called when the requests fails.
    public var onFailure: ((_ response: ImagePipeline.Error) -> Void)?

    /// Gets called when the request is completed.
    public var onCompletion: ((_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void)?

    public var pipeline: ImagePipeline = .shared
    private var task: ImageTask?

    // publisher support
    private var lastResponse: ImageResponse?
    private var cancellable: AnyCancellable?

    deinit {
        cancel()
    }

    public init() {}

    // MARK: Load (ImageRequestConvertible)

    /// Starts loading the image if not already loaded and the download is not
    /// already in progress.
    public func load(_ request: ImageRequestConvertible) {
        reset()

        var request = request.asImageRequest()

        // Try to display the regular image if it is available in memory cache
        if let container = pipeline.cache[request] {
            imageContainer = container // Display progressive image
            if !container.isPreview {
                let response = ImageResponse(container: container, urlResponse: nil, cacheType: .memory)
                let result: Result<ImageResponse, ImagePipeline.Error> = .success(response)
                self.result = result
                self.didComplete(result)
                return // Nothing to do
            }
        }

        if request.priority != priority {
            request.priority = priority
        }

        isLoading = true
        progress = Progress(completed: 0, total: 0)
        let task = pipeline.loadImage(
            with: request,
            progress: { [weak self] response, completed, total in
                guard let self = self else { return }
                self.progress = Progress(completed: completed, total: total)
                if let container = response?.container {
                    self.imageContainer = container // Display progressively decoded image
                }
                self.onProgress?(response, completed, total)
            },
            completion: { [weak self] in
                self?.didFinishRequest(result: $0)
            }
        )
        self.task = task
        onStart?(task)
    }

    private func didFinishRequest(result: Result<ImageResponse, ImagePipeline.Error>) {
        task = nil
        isLoading = false
        if case .success(let response) = result {
            self.imageContainer = response.container
        }
        self.result = result
        didComplete(result)
    }

    private func didComplete(_ result: Result<ImageResponse, ImagePipeline.Error>) {
        switch result {
        case .success(let response): onSuccess?(response)
        case .failure(let error): onFailure?(error)
        }
        onCompletion?(result)
    }

    // MARK: Load (Publisher)

    /// Loads an image with the given publisher.
    ///
    /// - warning: Some `FetchImage` features, such as progress reporting and
    /// dynamically changing the request priority, are not available when
    /// working with a publisher.
    public func load<P: Publisher>(_ publisher: P) where P.Output == ImageResponse, P.Failure == ImagePipeline.Error {
        reset()

        // Not using `first()` because it also supported progressive decoding
        isLoading = true
        cancellable = publisher.sink(receiveCompletion: { [weak self] completion in
            guard let self = self else { return }
            self.isLoading = false
            switch completion {
            case .finished:
                if let response = self.lastResponse {
                    self.result = .success(response)
                } // else was cancelled, do nothing
            case .failure(let error):
                self.result = .failure(error)
            }
        }, receiveValue: { [weak self] response in
            guard let self = self else { return }
            self.lastResponse = response
            self.imageContainer = response.container
        })
    }

    // MARK: Cancel

    /// Marks the request as being cancelled. Continues to display a downloaded
    /// image.
    public func cancel() {
        // pipeline-based
        task?.cancel() // Guarantees that no more callbacks are will be delivered
        task = nil

        // publisher-based
        cancellable = nil

        // common
        if isLoading { isLoading = false }
    }

    /// Resets the `FetchImage` instance by cancelling the request and removing
    /// all of the state including the loaded image.
    public func reset() {
        cancel()

        // Avoid publishing unchanged values
        if isLoading { isLoading = false }
        if imageContainer != nil { imageContainer = nil }
        if result != nil { result = nil }
        lastResponse = nil // publisher-only
        if progress != Progress(completed: 0, total: 0) { progress = Progress(completed: 0, total: 0) }
    }

    // MARK: View

    public var view: SwiftUI.Image? {
        #if os(macOS)
        return image.map(Image.init(nsImage:))
        #else
        return image.map(Image.init(uiImage:))
        #endif
    }
}
