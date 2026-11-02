// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import SwiftUI

// NukeUI's API is written in Nuke types, so `import NukeUI` is enough to use it.
@_exported import Nuke

/// A view that asynchronously loads and displays an image.
///
/// ``LazyImage`` is designed to be similar to the native [`AsyncImage`](https://developer.apple.com/documentation/SwiftUI/AsyncImage),
/// but it loads images with `ImagePipeline`. You can take advantage of all of
/// its features, such as caching, prefetching, task coalescing, smart
/// background decompression, request priorities, and more.
@MainActor
public struct LazyImage<Content: View>: View {
    @StateObject private var viewModel = FetchImage()
    @Environment(\.optionalImagePipeline) private var environmentPipeline

    private var context: LazyImageContext?
    private var overrides = Overrides()
    private var makeContent: ((LazyImageState) -> Content)?
    private var transaction: Transaction
    private var pipeline: ImagePipeline?
    private var onStart: (@MainActor @Sendable (ImageTask) -> Void)?
    private var onDisappearBehavior: DisappearBehavior? = .cancel
    private var onCompletion: (@MainActor @Sendable (Result<ImageResponse, ImagePipeline.Error>) -> Void)?

    // MARK: Initializers

    /// Loads and displays an image using `SwiftUI.Image`.
    ///
    /// - Parameters:
    ///   - url: The image URL.
    public init(url: URL?) where Content == Image {
        if let url {
            self.init(request: ImageRequest(url: url))
        } else {
            self.init(request: nil)
        }
    }

    /// Loads and displays an image using `SwiftUI.Image`.
    ///
    /// - Parameters:
    ///   - request: The image request.
    public init(request: ImageRequest?) where Content == Image {
        if let request {
            self.context = LazyImageContext(request: request)
        }
        self.transaction = Transaction(animation: nil)
    }

    /// Loads an image and displays custom content for each state.
    ///
    /// See also ``init(request:transaction:content:)``
    public init(
        url: URL?,
        transaction: Transaction = Transaction(animation: nil),
        @ViewBuilder content: @escaping (LazyImageState) -> Content
    ) {
        if let url {
            self.init(request: ImageRequest(url: url), transaction: transaction, content: content)
        } else {
            self.init(request: nil, transaction: transaction, content: content)
        }
    }

    /// Loads an image and displays custom content for each state.
    ///
    /// - Parameters:
    ///   - request: The image request.
    ///   - transaction: By default, transaction with no animations.
    ///   - content: The view to show for each of the image loading states.
    ///
    /// ```swift
    /// LazyImage(request: $0) { state in
    ///     if let image = state.image {
    ///         image // Displays the loaded image.
    ///     } else if state.error != nil {
    ///         Color.red // Indicates an error.
    ///     } else {
    ///         Color.blue // Acts as a placeholder.
    ///     }
    /// }
    /// ```
    public init(
        request: ImageRequest?,
        transaction: Transaction = Transaction(animation: nil),
        @ViewBuilder content: @escaping (LazyImageState) -> Content
    ) {
        if let request {
            self.context = LazyImageContext(request: request)
        }
        self.transaction = transaction
        self.makeContent = content
    }

    // MARK: Options

    /// Sets processors to be applied to the image.
    ///
    /// These processors replace any processors defined in the request, and
    /// `[]` removes them. `nil` keeps the request's own processors, and it
    /// also takes back an earlier call: the last call wins. This differs from
    /// ``FetchImage/processors`` and ``LazyImageView/processors``, which only
    /// apply when the request has no processors of its own.
    public consuming func processors(_ processors: [any ImageProcessing]?) -> Self {
        map { $0.overrides.processors = processors }
    }

    /// Sets the priority of the requests, replacing the request's own
    /// priority. `nil` keeps the request's own priority, and it also takes
    /// back an earlier call: the last call wins.
    ///
    /// A change updates the priority of the request that is already running
    /// instead of restarting it.
    public consuming func priority(_ priority: ImageRequest.Priority?) -> Self {
        map { $0.overrides.priority = priority }
    }

    /// Changes the underlying pipeline used for image loading.
    ///
    /// This takes precedence over the pipeline in the environment, which is set
    /// with ``SwiftUICore/View/imagePipeline(_:)``. Without either,
    /// ``ImagePipeline/shared`` is used.
    public consuming func pipeline(_ pipeline: ImagePipeline) -> Self {
        map { $0.pipeline = pipeline }
    }

    /// Defines the behavior when the view disappears.
    @frozen public enum DisappearBehavior {
        /// Cancels the current request but keeps the presentation state of
        /// the already displayed image.
        case cancel
        /// Lowers the request's priority to very low.
        case lowerPriority
    }

    /// Gets called when the request is started.
    public consuming func onStart(_ closure: @escaping @MainActor @Sendable (ImageTask) -> Void) -> Self {
        map { $0.onStart = closure }
    }

    /// Changes the behavior when the view disappears. By default, the current
    /// request is canceled. Pass `nil` to disable any behavior on disappear.
    public consuming func onDisappear(_ behavior: DisappearBehavior?) -> Self {
        map { $0.onDisappearBehavior = behavior }
    }

    /// Gets called when the current request is completed.
    public consuming func onCompletion(_ closure: @escaping @MainActor @Sendable (Result<ImageResponse, ImagePipeline.Error>) -> Void) -> Self {
        map { $0.onCompletion = closure }
    }

    /// The pipeline the view loads with: its own, then the environment's, then
    /// ``ImagePipeline/shared``, which is read here because it can be assigned
    /// at any time.
    private var resolvedPipeline: ImagePipeline {
        pipeline ?? environmentPipeline ?? .shared
    }

    private consuming func map(_ closure: (inout LazyImage) -> Void) -> Self {
        var copy = self
        closure(&copy)
        return copy
    }

    // MARK: Body

    public var body: some View {
        let update = Update(view: self)
        ZStack {
            let state: LazyImageState = update.memoryCacheHit.map(MemoryCacheHit.init) ?? viewModel
            if let makeContent {
                makeContent(state)
            } else {
                makeDefaultContent(for: state)
            }
        }
        .onAppear { update.view.onAppear(update) }
        .onDisappear { onDisappear() }
#if os(visionOS)
        // The one-parameter form is deprecated in every visionOS. This one
        // calls the closure of the current update, not the previous one, but
        // reads nothing from `self`, so the two behave the same.
        .onChange(of: update) { _, update in update.view.onChange(update) }
#else
        .onChange(of: update) { $0.view.onChange($0) }
#endif
    }

    /// Returns the image to draw while the view model hasn't loaded the request
    /// yet: the memory cache's, if it has one, so that this update already
    /// shows it and not a placeholder or the previous image.
    ///
    /// `onAppear` or `onChange` then loads the same image, to report it like
    /// any other load, and passes it along so that it stays even if the cache
    /// has lost it by then. That load publishes the image, which costs a second
    /// render of what's on screen: `FetchImage` can't take it silently because
    /// a `@Published` property always notifies, and they are its public API.
    ///
    /// Only the memory cache: it takes about a microsecond, and the disk cache
    /// takes a read and a decode, which the load does off the main thread.
    private func memoryCacheHit(for context: LazyImageContext?, pipeline: ImagePipeline) -> ImageResponse? {
        guard let context, !isLoaded(context, pipeline: pipeline) else { return nil }
        return viewModel.memoryCacheHit(for: context.request, pipeline: pipeline)
    }

    /// The view as of an update, compared by what it loads. The action of
    /// `onChange(of:perform:)` is the closure from the previous update, so the
    /// view reads its current options from here and not from that `self`.
    private struct Update: Equatable {
        let view: LazyImage
        /// The request with the modifiers applied, made once per update. It
        /// has to be a snapshot: a processor's identifier can change in place,
        /// and reading it again in `==` would see the new one on both sides.
        let context: LazyImageContext?
        /// The pipeline the view resolves to, made once per update for the same
        /// reason. The environment is only read in `body`, and the action runs
        /// later.
        let pipeline: ImagePipeline
        /// What this update draws instead of the view model's state, and the
        /// load that follows it finishes with.
        let memoryCacheHit: ImageResponse?

        @MainActor
        init(view: LazyImage) {
            let context = view.overrides.applied(to: view.context)
            let pipeline = view.resolvedPipeline
            self.view = view
            self.context = context
            self.pipeline = pipeline
            self.memoryCacheHit = view.memoryCacheHit(for: context, pipeline: pipeline)
        }

        static func == (lhs: Update, rhs: Update) -> Bool {
            lhs.context == rhs.context && lhs.pipeline === rhs.pipeline
        }
    }

    @ViewBuilder
    private func makeDefaultContent(for state: LazyImageState) -> some View {
        // `nil` for everything that isn't animated. The initializer carries
        // the still the decoder produced along with the animation, so that the
        // cell isn't blank for as long as the first frame takes to decode.
        if let container = state.imageContainer, let animation = AnimatedImage(container: container) {
            animation
        } else if let image = state.image {
            image
        } else {
            Color(.secondarySystemBackground)
        }
    }

    private func onAppear(_ update: Update) {
        // Unless the disappear behavior is `.cancel`, the request keeps running
        // off screen, and restarting it would discard what it has downloaded.
        let isStillLoading = viewModel.isLoading && isLoaded(update.context, pipeline: update.pipeline)
        configure(pipeline: update.pipeline)
        // Undo the priority lowered by the `.lowerPriority` disappear behavior.
        viewModel.priority = update.context?.request.priority
        if !isStillLoading {
            load(update)
        }
    }

    private func onChange(_ update: Update) {
        let isAlreadyLoaded = isLoaded(update.context, pipeline: update.pipeline)
        configure(pipeline: update.pipeline)
        // Before the load, which would otherwise start with the priority of
        // the previous request. If it's only the priority that changed, this
        // is all there is to do.
        viewModel.priority = update.context?.request.priority
        if !isAlreadyLoaded {
            load(update)
        }
    }

    private func load(_ update: Update) {
        viewModel.load(update.context?.request, memoryCacheHit: update.memoryCacheHit?.container)
    }

    private func configure(pipeline: ImagePipeline) {
        viewModel.transaction = transaction
        viewModel.pipeline = pipeline
        viewModel.onStart = onStart
        viewModel.onCompletion = onCompletion
    }

    /// Returns `true` if the view model has loaded, or is loading, the given
    /// request from the given pipeline, whatever its priority.
    private func isLoaded(_ context: LazyImageContext?, pipeline: ImagePipeline) -> Bool {
        guard let context, let request = viewModel.currentRequest else { return false }
        return viewModel.pipeline === pipeline && context.request.loadsSameImage(as: request)
    }

    private func onDisappear() {
        guard let behavior = onDisappearBehavior else { return }
        switch behavior {
        case .cancel:
            viewModel.cancel()
        case .lowerPriority:
            viewModel.priority = .veryLow
        }
    }
}

/// The state of a load that found its image in the memory cache, the way
/// `FetchImage` reports it once it has loaded it.
private struct MemoryCacheHit: LazyImageState {
    let response: ImageResponse

    var result: Result<ImageResponse, ImagePipeline.Error>? { .success(response) }
    var imageContainer: ImageContainer? { response.container }
    var isLoading: Bool { false }
    var progress: ImageTask.Progress { FetchImage.noProgress }
}

/// What the `processors` and `priority` modifiers set. `nil` leaves the
/// request's own value. The modifiers store their arguments here instead of
/// writing them into the request, so that the last call wins and a later
/// `nil` takes back an earlier value.
private struct Overrides {
    var processors: [any ImageProcessing]?
    var priority: ImageRequest.Priority?

    func applied(to context: LazyImageContext?) -> LazyImageContext? {
        guard var context, processors != nil || priority != nil else { return context }
        if let processors { context.request.processors = processors }
        if let priority { context.request.priority = priority }
        return context
    }
}

private struct LazyImageContext: Equatable {
    var request: ImageRequest

    static func == (lhs: LazyImageContext, rhs: LazyImageContext) -> Bool {
        lhs.request.loadsSameImage(as: rhs.request) && lhs.request.priority == rhs.request.priority
    }
}

#if DEBUG
struct LazyImage_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LazyImageDemoView()
                .previewDisplayName("LazyImage")

            LazyImage(url: URL(string: "https://kean.blog/images/pulse/01.png"))
                .previewDisplayName("LazyImage (Default)")

            AsyncImage(url: URL(string: "https://kean.blog/images/pulse/01.png"))
                .previewDisplayName("AsyncImage")
        }
    }
}

// This demonstrates that the view reacts correctly to the URL changes.
private struct LazyImageDemoView: View {
    @State var url = URL(string: "https://kean.blog/images/pulse/01.png")
    @State var isBlured = false
    @State var imageViewId = UUID()

    var body: some View {
        VStack {
            Spacer()

            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                }
            }
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
            .processors(isBlured ? [ImageProcessors.GaussianBlur()] : [])
#endif
            .id(imageViewId) // Example of how to implement retry

            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Button("Change Image") {
                    if url == URL(string: "https://kean.blog/images/pulse/01.png") {
                        url = URL(string: "https://kean.blog/images/pulse/02.png")
                    } else {
                        url = URL(string: "https://kean.blog/images/pulse/01.png")
                    }
                }
                Button("Retry") { imageViewId = UUID() }
                Toggle("Apply Blur", isOn: $isBlured)
            }
            .padding()
#if os(iOS) || os(tvOS) || os(macOS) || os(visionOS)
            .background(Material.ultraThick)
#endif
        }
    }
}
#endif
