// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

/// Loads images and reports every change of a load as a ``State``.
///
/// `ImageLoader` is the load logic behind ``LazyImageView``: it cancels what
/// was loading, applies its options to the request, checks the memory cache
/// synchronously, runs the task, and describes each step as a ``State``. It
/// doesn't display anything: that is up to whoever receives the state.
///
/// The simplest way to use it is to load an image into an image view:
///
/// ```swift
/// ImageLoader.load(url, into: imageView)
/// ```
///
/// To display the image in anything else, pass a closure that draws the state:
///
/// ```swift
/// ImageLoader.load(url, into: cell) { cell, state in
///     cell.posterView.image = state.image
///     cell.spinner.isHidden = !state.isLoading
/// }
/// ```
///
/// Both attach a loader to the object, so a new load into the same object
/// cancels the previous one, and deallocating the object cancels its load. To
/// configure a loader up front, or to receive its states in a delegate,
/// create one and keep it:
///
/// ```swift
/// final class PosterCell: UICollectionViewCell, ImageLoaderDelegate {
///     private let loader = ImageLoader()
///
///     func imageLoader(_ loader: ImageLoader, didUpdate state: ImageLoader.State) {
///         posterView.image = state.image
///     }
/// }
/// ```
///
/// Starting a load is synchronous, so an image found in the memory cache is
/// displayed before `load` returns. To wait for the outcome, await the
/// returned ``Handle``:
///
/// ```swift
/// let response = try await ImageLoader.load(url, into: imageView).response
/// ```
///
/// An image doesn't have to come from the pipeline. To report the states of
/// any async function, pass it to ``load(_:)-(()->ImageResponse)``:
///
/// ```swift
/// loader.load { try await pipeline.image(for: url) }
/// ```
@MainActor
public final class ImageLoader {

    // MARK: Options

    /// The pipeline used for loading images. ``ImagePipeline/shared`` by
    /// default.
    public var pipeline: ImagePipeline

    /// Processors to be applied to the requests that have none of their own.
    /// `[]` by default.
    public var processors: [any ImageProcessing] = []

    /// Overrides the priority of the requests. `nil` by default, which uses
    /// the request's own priority. A change updates the running task in place.
    public var priority: ImageRequest.Priority? {
        didSet {
            state.task?.priority = priority ?? state.request?.priority ?? .normal
        }
    }

    /// If `false`, the progressive previews produced by the pipeline aren't
    /// reported. `true` by default.
    public var isProgressiveRenderingEnabled = true

    /// If `true`, a new load keeps the previous image in
    /// ``State/imageContainer`` until it has an image of its own: a preview
    /// or the final image. The previous image is dropped if the new load
    /// fails, and stays if it is cancelled. `false` by default.
    public var keepsPreviousImage = false

    // MARK: State

    /// The current state.
    public private(set) var state = State()

    /// The task of the current load, while it runs.
    public var task: ImageTask? { state.task }

    /// Receives every change of the ``state``.
    public weak var delegate: (any ImageLoaderDelegate)?

    /// Receives every change of the ``state``, before the ``delegate``.
    var onUpdate: (@MainActor (State) -> Void)?

    /// The outcome of the current load. It is resolved when the load
    /// finishes, is cancelled, or is replaced by a new load.
    fileprivate var outcome: Outcome?

    /// The Swift task of the current load from a closure.
    private var asyncTask: Task<Void, Never>?

    /// Incremented on every update, so that an update started from a callback
    /// isn't followed by a stale one.
    private var updateCount = 0

    /// Creates a loader.
    public init(pipeline: ImagePipeline = .shared) {
        self.pipeline = pipeline
    }

    deinit {
        state.task?.cancel()
        asyncTask?.cancel()
        // The events of the task no longer reach the loader, so whoever awaits
        // the outcome has to be told here.
        if let outcome {
            Task { @MainActor in outcome.resolve(.failure(.cancelled)) }
        }
    }

    // MARK: Loading

    /// Loads an image with the given URL, and cancels what was loading
    /// before it.
    ///
    /// - returns: A handle to the load, to await its outcome or cancel it.
    @discardableResult
    public func load(_ url: URL?) -> Handle {
        load(url.map { ImageRequest(url: $0) })
    }

    /// Loads an image with the given request, and cancels what was loading
    /// before it.
    ///
    /// The memory cache is checked synchronously: if it has the final image,
    /// the load finishes before this method returns, and so does a `nil`
    /// request, with ``ImagePipeline/Error/imageRequestMissing``. In both
    /// cases the only state is ``Event/finished(_:isSync:)``.
    ///
    /// - returns: A handle to the load, to await its outcome or cancel it.
    @discardableResult
    public func load(_ request: ImageRequest?) -> Handle {
        let previousImage = keepsPreviousImage ? state.imageContainer : nil
        cancelTask()

        // A load that finishes before this method returns needs no `Outcome`:
        // its handle just holds the result.
        guard let request else {
            let result: Result<ImageResponse, ImagePipeline.Error> = .failure(.imageRequestMissing)
            var state = State()
            state.event = .finished(result, isSync: true)
            state.result = result
            finish(state)
            return Handle(result: result)
        }

        var resolved = request
        if !processors.isEmpty && resolved.processors.isEmpty {
            resolved.processors = processors
        }
        if let priority {
            resolved.priority = priority
        }

        // Quick synchronous memory cache lookup.
        let cached = pipeline.cache[resolved]
        if let container = cached, !container.isPreview {
            let response = ImageResponse(container: container, request: resolved, cacheType: .memory)
            var state = State()
            state.event = .finished(.success(response), isSync: true)
            state.request = request
            state.imageContainer = container
            state.result = .success(response)
            finish(state)
            return Handle(result: .success(response))
        }

        let outcome = Outcome(loader: self)
        self.outcome = outcome

        // A callback rather than the public async/await API. The difference
        // is tiny, about 0.5 µs per load on the main thread, which goes to
        // creating the `AsyncStream` and the Swift task that reads it, but
        // it adds up with a load per cell. The async/await version:
        //
        //     let task = pipeline.imageTask(with: resolved)
        //     let events = task.events
        //     Task { [weak self] in
        //         for await event in events {
        //             guard let self else { return }
        //             self.handle(event, of: task)
        //         }
        //     }
        let task = pipeline.imageTask(with: resolved) { [weak self] event, task in
            self?.handle(event, of: task)
        }

        var state = State()
        state.event = .started(task)
        state.request = request
        state.task = task
        state.isLoading = true
        // A preview found in the memory cache, or the previous image
        state.imageContainer = cached ?? previousImage
        state.isPreviousImage = cached == nil && previousImage != nil
        update(state)
        return Handle(task: task, outcome: outcome)
    }

    /// Loads an image with the given async function, and cancels what was
    /// loading before it.
    ///
    /// The load is reported like any other, but it has no pipeline task and no
    /// request: ``State/task`` and ``State/request`` are `nil`, and so is
    /// the task of ``Event/started(_:)``. It reports no progress or previews,
    /// and doesn't use ``pipeline``, ``processors`` or ``priority``.
    ///
    /// Cancelling the load cancels the Swift task that runs `action`. The
    /// function isn't guaranteed to stop, and if it returns anyway, its
    /// result is discarded.
    ///
    /// - parameter action: Fetches the image. An error that isn't already an
    /// ``ImagePipeline/Error`` is reported as
    /// ``ImagePipeline/Error/dataLoadingFailed(error:)`` wrapping it, the same
    /// way the pipeline reports the errors thrown by the async
    /// ``ImageRequest`` sources.
    /// - returns: A handle to the load, to await its outcome or cancel it.
    @discardableResult
    public func load(_ action: @escaping () async throws -> ImageResponse) -> Handle {
        let previousImage = keepsPreviousImage ? state.imageContainer : nil
        cancelTask()

        let outcome = Outcome(loader: self)
        self.outcome = outcome

        // The task can't start before this method returns, so it never
        // finishes before the `started` state is reported.
        asyncTask = Task { [weak self] in
            let result: Result<ImageResponse, ImagePipeline.Error>
            do {
                result = .success(try await action())
            } catch {
                result = .failure(error as? ImagePipeline.Error ?? .dataLoadingFailed(error: error))
            }
            guard let self, self.outcome === outcome else {
                return // Released, cancelled, or replaced
            }
            asyncTask = nil
            handle(result: result)
        }

        var state = State()
        state.event = .started(nil)
        state.isLoading = true
        state.imageContainer = previousImage
        state.isPreviousImage = previousImage != nil
        update(state)
        return Handle(task: nil, outcome: outcome)
    }

    /// Cancels the current load. The image it displayed so far stays in the
    /// state.
    public func cancel() {
        guard state.isLoading else { return }
        cancelTask()
        var state = self.state
        state.event = .cancelled
        state.isLoading = false
        update(state)
    }

    /// Cancels the current load and clears the state.
    public func reset() {
        cancelTask()
        update(State())
    }

    private func cancelTask() {
        state.task?.cancel() // Its remaining events are ignored
        state.task = nil
        asyncTask?.cancel() // Its result is ignored
        asyncTask = nil
        if let outcome {
            self.outcome = nil
            outcome.resolve(.failure(.cancelled))
        }
    }

    // MARK: Handling Events

    private func handle(_ event: ImageTask.Event, of task: ImageTask) {
        guard task === state.task else {
            return // The load was cancelled or replaced
        }
        switch event {
        case .progress(let progress):
            var state = self.state
            state.event = .progress(progress)
            state.progress = progress
            update(state)
        case .preview(let preview):
            guard isProgressiveRenderingEnabled else { return }
            var state = self.state
            state.event = .preview(preview)
            state.imageContainer = preview.container
            state.isPreviousImage = false
            update(state)
        case .finished(let result):
            if task.isCancelled, case .failure(.cancelled) = result {
                cancel() // The task was cancelled directly
            } else {
                handle(result: result)
            }
        }
    }

    private func handle(result: Result<ImageResponse, ImagePipeline.Error>) {
        var state = self.state
        state.event = .finished(result, isSync: false)
        state.task = nil
        state.isLoading = false
        state.result = result
        switch result {
        case .success(let response):
            state.imageContainer = response.container
        case .failure:
            // Keeps a preview of this load, but not the image of a previous one
            if state.isPreviousImage {
                state.imageContainer = nil
            }
        }
        state.isPreviousImage = false
        finish(state)
    }

    private func finish(_ state: State) {
        let outcome = self.outcome
        self.outcome = nil
        if let result = state.result {
            outcome?.resolve(result)
        }
        update(state)
    }

    private func update(_ state: State) {
        self.state = state
        updateCount &+= 1
        let count = updateCount
        onUpdate?(state)
        // The closure may have started a new load, which the delegate has
        // already been told about.
        guard count == updateCount else { return }
        delegate?.imageLoader(self, didUpdate: state)
    }
}

// MARK: - State

extension ImageLoader {
    /// A snapshot of a load: what to display, and what just changed.
    public struct State: Sendable {
        /// What changed since the previous state.
        public internal(set) var event: Event = .reset

        /// The request of the load, as it was passed to ``ImageLoader/load(_:)-(ImageRequest?)``,
        /// before the processors and the priority of the loader are applied.
        public internal(set) var request: ImageRequest?

        /// The task of the load, while it runs. `nil` for a load from a
        /// closure.
        public internal(set) var task: ImageTask?

        /// The image to display: the final image, a progressive preview, or
        /// the previous image (see ``ImageLoader/keepsPreviousImage``). `nil`
        /// when there is nothing to display yet, which is where a placeholder
        /// goes.
        public internal(set) var imageContainer: ImageContainer?

        /// `true` when ``imageContainer`` is the image of a previous load,
        /// kept by ``ImageLoader/keepsPreviousImage``.
        public internal(set) var isPreviousImage = false

        /// `true` while the task runs.
        public internal(set) var isLoading = false

        /// The progress of the download.
        public internal(set) var progress = ImageTask.Progress(completed: 0, total: 0)

        /// The outcome of the load, once it finishes.
        public internal(set) var result: Result<ImageResponse, ImagePipeline.Error>?

        /// The image to display. See ``imageContainer``.
        public var image: PlatformImage? { imageContainer?.image }

        /// The error the load failed with, if it failed.
        public var error: ImagePipeline.Error? {
            if case .failure(let error) = result { return error }
            return nil
        }
    }

    /// What changed in a ``State``.
    ///
    /// A load that starts a task, or runs a closure, reports ``started(_:)``,
    /// any number of ``progress(_:)`` and ``preview(_:)``, and then
    /// ``finished(_:isSync:)``. A `nil` request and an image found in the
    /// memory cache report ``finished(_:isSync:)`` only, before `load`
    /// returns, so a reused cell is never cleared before it gets its image.
    public enum Event: Sendable {
        /// The load started a task, and the previous load is cancelled.
        /// ``State/imageContainer`` is a preview found in the memory cache, the
        /// previous image, or `nil`. The task is `nil` for a load from a
        /// closure.
        case started(ImageTask?)
        /// The download progressed.
        case progress(ImageTask.Progress)
        /// The pipeline produced a progressive preview, which is now the
        /// ``State/imageContainer``.
        case preview(ImageResponse)
        /// The load finished. `isSync` is `true` when it finished before
        /// `load` returned: the image was in the memory cache, or the request
        /// was `nil`.
        case finished(Result<ImageResponse, ImagePipeline.Error>, isSync: Bool)
        /// The load was cancelled with ``ImageLoader/cancel()``, or its task
        /// was cancelled.
        case cancelled
        /// The state was cleared with ``ImageLoader/reset()``. It is also the
        /// event of a loader that hasn't loaded anything.
        case reset
    }
}

// MARK: - Delegate

/// Receives the states of an ``ImageLoader``.
@MainActor
public protocol ImageLoaderDelegate: AnyObject {
    /// Called every time the state of the loader changes.
    func imageLoader(_ loader: ImageLoader, didUpdate state: ImageLoader.State)
}

// MARK: - Handle

extension ImageLoader {
    /// A handle to a load started by an ``ImageLoader``, to await its outcome
    /// or cancel it.
    ///
    /// A load that is cancelled, or replaced by a new load into the same
    /// loader, finishes with ``ImagePipeline/Error/cancelled``.
    public struct Handle: Sendable {
        /// The task of the load, or `nil` if it finished synchronously or runs
        /// a closure. Cancelling it cancels the load.
        public let task: ImageTask?

        private let source: Source

        private enum Source: Sendable {
            /// The load finished before it returned.
            case finished(Result<ImageResponse, ImagePipeline.Error>)
            case pending(Outcome)
        }

        init(task: ImageTask?, outcome: Outcome) {
            self.task = task
            self.source = .pending(outcome)
        }

        init(result: Result<ImageResponse, ImagePipeline.Error>) {
            self.task = nil
            self.source = .finished(result)
        }

        /// Returns the response of the load.
        ///
        /// It returns right away for a load that has already finished, such as
        /// an image found in the memory cache. Cancelling the Swift task that
        /// awaits the response cancels the load.
        public var response: ImageResponse {
            get async throws(ImagePipeline.Error) {
                try await result.get()
            }
        }

        /// Returns the outcome of the load.
        ///
        /// Cancelling the Swift task that awaits the result cancels the load.
        public var result: Result<ImageResponse, ImagePipeline.Error> {
            get async {
                let outcome: Outcome
                switch source {
                case .finished(let result):
                    return result
                case .pending(let pending):
                    outcome = pending
                }
                return await withTaskCancellationHandler {
                    await outcome.value()
                } onCancel: {
                    Task { @MainActor in outcome.cancel() }
                }
            }
        }

        /// Cancels the load, unless it has already finished or was replaced.
        @MainActor
        public func cancel() {
            if case .pending(let outcome) = source {
                outcome.cancel()
            }
        }
    }

    @MainActor
    final class Outcome {
        private(set) var result: Result<ImageResponse, ImagePipeline.Error>?
        private var continuations: [CheckedContinuation<Result<ImageResponse, ImagePipeline.Error>, Never>] = []
        private weak var loader: ImageLoader?

        init(loader: ImageLoader) {
            self.loader = loader
        }

        func value() async -> Result<ImageResponse, ImagePipeline.Error> {
            if let result {
                return result
            }
            return await withCheckedContinuation {
                continuations.append($0)
            }
        }

        func resolve(_ result: Result<ImageResponse, ImagePipeline.Error>) {
            guard self.result == nil else { return }
            self.result = result
            let continuations = self.continuations
            self.continuations = []
            for continuation in continuations {
                continuation.resume(returning: result)
            }
        }

        func cancel() {
            guard result == nil else { return }
            if let loader, loader.outcome === self {
                loader.cancel()
            } else {
                resolve(.failure(.cancelled))
            }
        }
    }
}

// MARK: - Loading Into Objects

extension ImageLoader {
    // Safe because it's never mutated.
    nonisolated(unsafe) private static let loaderAK = malloc(1)!

    /// Returns the loader attached to the object, and attaches a new one on
    /// first use.
    ///
    /// This is the loader the `load(_:into:)` functions use, so it is where
    /// to configure them, or to cancel their load. It lives as long as the
    /// object, and cancels its load when the object is deallocated.
    public static func loader(for object: AnyObject) -> ImageLoader {
        if let loader = objc_getAssociatedObject(object, loaderAK) as? ImageLoader {
            return loader
        }
        let loader = ImageLoader()
        objc_setAssociatedObject(object, loaderAK, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return loader
    }

    /// Loads an image with the given URL into the target, and calls `render`
    /// with every change of the state.
    ///
    /// See ``load(_:into:pipeline:render:)-(ImageRequest?,_,_,_)``.
    @discardableResult
    public static func load<Target: AnyObject>(
        _ url: URL?,
        into target: Target,
        pipeline: ImagePipeline? = nil,
        render: @escaping @MainActor (Target, State) -> Void
    ) -> Handle {
        load(url.map { ImageRequest(url: $0) }, into: target, pipeline: pipeline, render: render)
    }

    /// Loads an image with the given request into the target, and calls
    /// `render` with every change of the state.
    ///
    /// The load uses the loader attached to the target (see
    /// ``loader(for:)``), so it cancels the previous load into the same
    /// target. The target is held weakly, and passed to `render` rather than
    /// captured by it, which keeps the load from retaining it.
    ///
    /// ```swift
    /// ImageLoader.load(request, into: cell) { cell, state in
    ///     cell.posterView.image = state.image
    ///     cell.spinner.isHidden = !state.isLoading
    /// }
    /// ```
    ///
    /// - parameters:
    ///   - request: The image request. A `nil` request fails with
    ///   ``ImagePipeline/Error/imageRequestMissing``.
    ///   - target: The object to load the image into. It is held weakly.
    ///   - pipeline: The pipeline to load the image with. `nil` keeps the
    ///   pipeline of the attached loader, ``ImagePipeline/shared`` by default.
    ///   - render: Called with every change of the state, including the
    ///   synchronous ones made before this method returns.
    /// - returns: A handle to the load, to await its outcome or cancel it.
    @discardableResult
    public static func load<Target: AnyObject>(
        _ request: ImageRequest?,
        into target: Target,
        pipeline: ImagePipeline? = nil,
        render: @escaping @MainActor (Target, State) -> Void
    ) -> Handle {
        let loader = Self.loader(for: target)
        if let pipeline {
            loader.pipeline = pipeline
        }
        loader.onUpdate = { [weak target] state in
            if let target {
                render(target, state)
            }
        }
        return loader.load(request)
    }
}
