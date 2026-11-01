// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Combine // For `ObservableObject` and `@Published`
import Nuke

/// An observable object that simplifies image loading in SwiftUI.
@MainActor
public final class FetchImage: ObservableObject, Identifiable {
    /// Returns the current fetch result.
    @Published public private(set) var result: Result<ImageResponse, ImagePipeline.Error>?

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
    ///
    /// Returns `ImageTask.Progress`, the same struct the pipeline reports.
    /// `NukeUI` no longer has a progress type of its own: `FetchImage.Progress`
    /// is a deprecated typealias for it.
    ///
    /// - note: The updates are only published to the observers if you read the
    /// property, so the views that don't display the progress aren't
    /// invalidated every time a chunk of data arrives.
    public var progress: ImageTask.Progress {
        isProgressObserved = true
        return _progress
    }

    private static let noProgress = ImageTask.Progress(completed: 0, total: 0)

    // Set the first time `progress` is read; see the property for the reason.
    private var isProgressObserved = false

    private var _progress = FetchImage.noProgress {
        willSet {
            guard isProgressObserved else { return }
            objectWillChange.send()
        }
    }

    /// Overrides the priority of the current and future requests. When `nil`
    /// (the default), the request's own priority is used. Can be updated while
    /// a task is already running.
    public var priority: ImageRequest.Priority? {
        get { loader.priority }
        set { loader.priority = newValue }
    }

    /// A pipeline used for performing image requests.
    public var pipeline: ImagePipeline {
        get { loader.pipeline }
        set { loader.pipeline = newValue }
    }

    /// Image processors to be applied unless the processors are provided in the
    /// request. `[]` by default.
    public var processors: [any ImageProcessing] {
        get { loader.processors }
        set { loader.processors = newValue }
    }

    /// Gets called when the request is started.
    public var onStart: (@MainActor @Sendable (ImageTask) -> Void)?

    /// Gets called when the current request is completed.
    public var onCompletion: (@MainActor @Sendable (Result<ImageResponse, ImagePipeline.Error>) -> Void)?

    // The load logic: cancellation, the memory cache lookup, the options, and
    // the stale results. `FetchImage` publishes what the loader reports.
    private let loader = ImageLoader()

    /// The request passed to the last `load(_:)` call, before
    /// ``priority`` and ``processors`` are applied to it. `nil` for a load
    /// from an async function.
    var currentRequest: ImageRequest? { loader.state.request }

    /// Initializes the image. To load an image, use one of the `load()` methods.
    public init() {
        loader.onUpdate = { [weak self] in self?.apply($0) }
    }

    // MARK: Loading Images

    /// Loads an image with the given URL.
    public func load(_ url: URL?) {
        // Not `url.map`: a closure inherits the actor and checks for it, which
        // traps for Swift 5 code that gets here off the main thread (see 13.0.6).
        if let url {
            load(ImageRequest(url: url))
        } else {
            load(nil as ImageRequest?)
        }
    }

    /// Loads an image with the given request.
    ///
    /// If it's already loading the same image, whatever the priority, the
    /// task keeps running and gets the new priority.
    public func load(_ request: ImageRequest?) {
        assert(Thread.isMainThread, "Must be called from the main thread")
        loader.load(request)
    }

    // MARK: Load (Async/Await)

    /// Loads and displays an image using the given async function.
    ///
    /// - parameter action: Fetches the image. An error that isn't already an
    /// ``ImagePipeline/Error`` is reported as
    /// ``ImagePipeline/Error/dataLoadingFailed(error:)`` wrapping it, the same
    /// way the pipeline reports the errors thrown by the async
    /// ``ImageRequest`` sources.
    public func load(_ action: @escaping () async throws -> ImageResponse) {
        loader.load(action)
    }

    // MARK: Reload

    /// Loads the request of the last load again.
    ///
    /// Use it to retry a load that failed or was cancelled. A load that is
    /// still running keeps running. To retry automatically, set a
    /// ``ImagePipeline/RetryPolicy`` on the pipeline or the request.
    ///
    /// The last load has nothing to repeat if it was from an async function or a
    /// `nil` request, or if it was reset.
    public func reload() {
        loader.reload()
    }

    // MARK: Cancel

    /// Marks the request as being cancelled. Continues to display a downloaded image.
    public func cancel() {
        loader.cancel()
    }

    /// Resets the `FetchImage` instance by cancelling the request and removing
    /// all of the state including the loaded image.
    public func reset() {
        loader.reset()
    }

    // MARK: Applying the State

    // Each case publishes only what changed, and calls the callbacks last, so
    // that a callback can start a new load.
    private func apply(_ state: ImageLoader.State) {
        switch state.event {
        case .started(let task):
            handleStart(state, task: task)
        case .progress(let progress):
            _progress = progress
        case .preview:
            withTransaction(transaction) {
                imageContainer = state.imageContainer
            }
        case let .finished(result, isSynchronous):
            // An image found in the memory cache has no progress, which also
            // clears the one of a load it replaced.
            if _progress != state.progress { _progress = state.progress }
            if isSynchronous {
                // Animation isn't used when the image is available in the memory cache.
                finish(with: result, container: state.imageContainer)
            } else {
                withTransaction(transaction) {
                    finish(with: result, container: state.imageContainer)
                }
            }
        case .cancelled:
            if isLoading { isLoading = false }
        case .reset:
            clearState()
        }
    }

    private func handleStart(_ state: ImageLoader.State, task: ImageTask?) {
        if _progress != Self.noProgress { _progress = Self.noProgress }
        if result != nil { result = nil }
        // A preview found in the memory cache, or `nil`
        if imageContainer != nil || state.imageContainer != nil {
            imageContainer = state.imageContainer
        }
        if !isLoading { isLoading = true }
        if let task {
            onStart?(task)
        }
    }

    private func finish(with result: Result<ImageResponse, ImagePipeline.Error>, container: ImageContainer?) {
        if isLoading { isLoading = false }
        // Set together with the result to avoid a nil flicker.
        imageContainer = container
        self.result = result
        onCompletion?(result)
    }

    // Avoids publishing unchanged values
    private func clearState() {
        if _progress != Self.noProgress { _progress = Self.noProgress }
        if isLoading { isLoading = false }
        if imageContainer != nil { imageContainer = nil }
        if result != nil { result = nil }
    }
}
