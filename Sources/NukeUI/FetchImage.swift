// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Combine
import Nuke

/// An observable object that simplifies image loading in SwiftUI.
@MainActor
public final class FetchImage: ObservableObject, Identifiable {
    /// Returns the current fetch result.
    @Published public private(set) var result: Result<ImageResponse, Error>?

    /// Returns the fetched image.
    public var image: Image? {
        guard let imageContainer else { return nil }
#if os(macOS)
        return Image(nsImage: imageContainer.image)
#else
        return Image(uiImage: imageContainer.image)
#endif
    }

    /// Returns the fetched image.
    ///
    /// - note: In case the pipeline has the `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    @Published public private(set) var imageContainer: ImageContainer?

    /// Returns `true` if the image is being loaded.
    @Published public private(set) var isLoading = false

    /// Animations to be used when displaying the loaded images. By default, `nil`.
    ///
    /// - note: Animation isn't used when the image is available in the memory cache.
    public var transaction = Transaction(animation: nil)

    /// The progress of the current image download.
    public var progress: Progress {
        if _progress == nil {
            _progress = Progress()
        }
        return _progress!
    }

    private var _progress: Progress?

    /// The download progress.
    public final class Progress: ObservableObject {
        /// The number of bytes that the task has received.
        @Published public internal(set) var completed: Int64 = 0

        /// A best-guess upper bound on the number of bytes of the resource.
        @Published public internal(set) var total: Int64 = 0

        /// Returns the fraction of the completion.
        public var fraction: Float {
            guard total > 0 else { return 0 }
            return min(1, Float(completed) / Float(total))
        }
    }

    /// Overrides the priority of the current and future requests. When `nil`
    /// (the default), the request's own priority is used. Can be updated while
    /// a task is already running.
    public var priority: ImageRequest.Priority? {
        didSet {
            if let priority {
                imageTask?.priority = priority
            }
        }
    }

    /// A pipeline used for performing image requests.
    public var pipeline: ImagePipeline = .shared

    /// Image processors to be applied unless the processors are provided in the
    /// request. `[]` by default.
    public var processors: [any ImageProcessing] = []

    /// Gets called when the request is started.
    public var onStart: (@MainActor @Sendable (ImageTask) -> Void)?

    /// Gets called when the current request is completed.
    public var onCompletion: (@MainActor @Sendable (Result<ImageResponse, Error>) -> Void)?

    private var imageTask: ImageTask?
    private var lastResponse: ImageResponse?
    private var cancellable: AnyCancellable?

    deinit {
        imageTask?.cancel()
    }

    /// Initializes the image. To load an image, use one of the `load()` methods.
    public init() {}

    // MARK: Loading Images

    /// Loads an image with the given URL.
    public func load(_ url: URL?) {
        if let url {
            load(ImageRequest(url: url))
        } else {
            load(nil as ImageRequest?)
        }
    }

    /// Loads an image with the given request.
    public func load(_ request: ImageRequest?) {
        assert(Thread.isMainThread, "Must be called from the main thread")

        cancel()

        guard var request else {
            reset()
            handle(result: .failure(ImagePipeline.Error.imageRequestMissing))
            return
        }

        if !processors.isEmpty && request.processors.isEmpty {
            request.processors = processors
        }
        if let priority {
            request.priority = priority
        }

        // Quick synchronous memory cache lookup
        let cached = pipeline.cache[request]
        if let image = cached, !image.isPreview {
            // Set imageContainer and result directly to avoid a nil flicker.
            clearLoadingState()
            let response = ImageResponse(container: image, request: request, cacheType: .memory)
            imageContainer = image
            result = .success(response)
            onCompletion?(.success(response))
            return
        }

        reset()

        if let image = cached {
            imageContainer = image // Display progressive image
        }

        isLoading = true

        let task = pipeline.loadImage(
            with: request,
            progress: { [weak self] response, completed, total in
                guard let self else { return }
                if let response {
                    withTransaction(self.transaction) {
                        self.handle(preview: response)
                    }
                } else {
                    self._progress?.completed = completed
                    self._progress?.total = total
                }
            },
            completion: { [weak self] result in
                guard let self else { return }
                withTransaction(self.transaction) {
                    self.handle(result: result.mapError { $0 })
                }
            }
        )
        imageTask = task
        onStart?(task)
    }

    private func handle(preview: ImageResponse) {
        // Display progressively decoded image
        self.imageContainer = preview.container
    }

    private func handle(result: Result<ImageResponse, Error>) {
        isLoading = false
        imageTask = nil

        if case .success(let response) = result {
            self.imageContainer = response.container
        }
        self.result = result
        self.onCompletion?(result)
    }

    // MARK: Load (Async/Await)

    /// Loads and displays an image using the given async function.
    ///
    /// - parameter action: Fetches the image.
    public func load(_ action: @escaping () async throws -> ImageResponse) {
        reset()
        isLoading = true

        let task = Task {
            do {
                let response = try await action()
                withTransaction(transaction) {
                    handle(result: .success(response))
                }
            } catch {
                handle(result: .failure(error))
            }
        }

        cancellable = AnyCancellable { task.cancel() }
    }

    // MARK: Load (Combine)

    /// Loads an image with the given publisher.
    ///
    /// - important: Some `FetchImage` features, such as progress reporting and
    /// dynamically changing the request priority, are not available when
    /// working with a publisher.
    public func load<P: Publisher>(_ publisher: P) where P.Output == ImageResponse {
        reset()

        // Not using `first()` because it should support progressive decoding
        isLoading = true
        cancellable = publisher.sink(receiveCompletion: { [weak self] completion in
            guard let self else { return }
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
            guard let self else { return }
            self.lastResponse = response
            self.imageContainer = response.container
        })
    }

    // MARK: Cancel

    /// Marks the request as being cancelled. Continues to display a downloaded image.
    public func cancel() {
        // pipeline-based
        imageTask?.cancel() // Guarantees that no more callbacks will be delivered
        imageTask = nil

        // publisher-based
        cancellable = nil
    }

    /// Resets the `FetchImage` instance by cancelling the request and removing
    /// all of the state including the loaded image.
    public func reset() {
        cancel()

        // Avoid publishing unchanged values
        clearLoadingState()
        if imageContainer != nil { imageContainer = nil }
        if result != nil { result = nil }
        lastResponse = nil // publisher-only
    }

    private func clearLoadingState() {
        if isLoading { isLoading = false }
        if _progress != nil { _progress = nil }
    }
}
