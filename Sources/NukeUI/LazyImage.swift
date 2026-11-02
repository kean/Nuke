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
    // In a box: SwiftUI copies the view on every update, and a view that sets
    // none of these options, which is most of them, pays for one pointer.
    private var options: Box<Options>?

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

    /// The view with different content, and everything else as it was set.
    private init<Other>(copying other: consuming LazyImage<Other>, @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.context = other.context
        self.overrides = other.overrides
        self.makeContent = content
        self.transaction = other.transaction
        self.pipeline = other.pipeline
        self.onStart = other.onStart
        self.onDisappearBehavior = switch other.onDisappearBehavior {
        case .cancel: .cancel
        case .lowerPriority: .lowerPriority
        case nil: nil
        }
        self.onCompletion = other.onCompletion
        self.options = other.options
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

    /// Keeps the current image on screen while a new one loads, instead of
    /// showing the placeholder in between. The view keeps it until the new
    /// load has an image of its own, a preview or the final image, and drops
    /// it if the load fails. `false` by default.
    ///
    /// While the previous image is displayed, ``LazyImageState/image`` isn't
    /// `nil` and ``LazyImageState/isLoading`` is `true`.
    public consuming func keepsPreviousImage(_ keepsPreviousImage: Bool = true) -> Self {
        mapOptions { $0.keepsPreviousImage = keepsPreviousImage }
    }

    /// Loads the image again when the given value changes.
    ///
    /// ```swift
    /// @State private var attempt = 0
    ///
    /// var body: some View {
    ///     LazyImage(url: url)
    ///         .reload(id: attempt)
    ///     Button("Retry") { attempt += 1 }
    /// }
    /// ```
    ///
    /// The view stays, with its state, and only the load starts over, the way
    /// ``LazyImageState/reload()`` does it from inside of the content. To keep
    /// the current image on screen in the meantime, use ``keepsPreviousImage(_:)``.
    ///
    /// A load that is still running keeps running. If the memory cache has the
    /// image, it is what gets displayed. To skip the caches, load a request with
    /// ``ImageRequest/Options-swift.struct/reloadIgnoringCachedData``.
    public consuming func reload(id: some Hashable) -> Self {
        let id = AnyHashable(id)
        return mapOptions { $0.reloadID = id }
    }

    /// Sets the view to display when the load fails, in place of the content
    /// of the view, whether it's the default one or the one from the `content`
    /// closure.
    ///
    /// ```swift
    /// LazyImage(url: url)
    ///     .failureView { state in
    ///         Button("Retry") { state.reload() }
    ///     }
    /// ```
    ///
    /// - parameter content: Receives the same state as the `content` closure,
    /// so it can read ``LazyImageState/error`` and call ``LazyImageState/reload()``.
    public consuming func failureView<Failure: View>(@ViewBuilder _ content: @escaping (LazyImageState) -> Failure) -> LazyImage<some View> {
        // A new `Content`, which `some View` hides, and not an `AnyView` in a
        // branch of `body`, which every view would pay for (see `body`).
        let makeContent = makeContent
        return LazyImage<_>(copying: self) { state in
            if state.error != nil {
                content(state)
            } else {
                makeStateContent(makeContent, for: state)
            }
        }
    }

    /// Sets the transition to display a new image with: the first one, and
    /// the one that replaces it after the request changes. It removes what
    /// the view displayed before, such as the placeholder, with the same
    /// transition.
    ///
    /// ```swift
    /// LazyImage(url: url)
    ///     .imageTransition(.opacity, animation: .easeInOut(duration: 0.33))
    /// ```
    ///
    /// Use it instead of the `transaction` of the initializer, which it
    /// replaces, for a transition that doesn't depend on how the `content`
    /// closure is written. The view runs it by giving the content a new
    /// identity, so any state the content owns starts over with a new image.
    ///
    /// - parameters:
    ///   - transition: The transition, applied in both directions. For a
    ///   different one in each, use `AnyTransition.asymmetric(insertion:removal:)`.
    ///   - animation: The animation that runs it.
    ///   - onMemoryCacheHit: By default, an image that is in the memory cache
    ///   is displayed with no transition. Otherwise, a list would run it for
    ///   every cell that scrolls back. Pass `true` to run it anyway.
    public consuming func imageTransition(_ transition: AnyTransition, animation: Animation = .default, onMemoryCacheHit: Bool = false) -> LazyImage<some View> {
        let makeContent = makeContent
        var copy = mapOptions { $0.animatesMemoryCacheHits = onMemoryCacheHit }
        copy.transaction = Transaction(animation: animation)
        return LazyImage<_>(copying: copy) { state in
            makeStateContent(makeContent, for: state)
                .modifier(ImageTransitionModifier(container: state.imageContainer, transition: transition))
        }
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

    private var reloadID: AnyHashable? { options?.value.reloadID }

    private consuming func map(_ closure: (inout LazyImage) -> Void) -> Self {
        var copy = self
        closure(&copy)
        return copy
    }

    private consuming func mapOptions(_ closure: (inout Options) -> Void) -> Self {
        map {
            var options = $0.options?.value ?? Options()
            closure(&options)
            $0.options = Box(options)
        }
    }

    // MARK: Body

    public var body: some View {
        // Every cell of a list pays for what's here, so what only some views
        // use goes in their `Content`. Moving these lines into a property of
        // their own costs 1% of the instructions a cell takes to show up, and
        // two more branches for the modifiers 0.3%.
        ZStack {
            if let makeContent {
                makeContent(viewModel)
            } else {
                makeDefaultContent(for: viewModel)
            }
        }
        .onAppear { onAppear() }
        .onDisappear { onDisappear() }
#if os(visionOS)
        // The one-parameter form is deprecated in every visionOS. This one
        // calls the closure of the current update, not the previous one, but
        // reads nothing from `self`, so the two behave the same.
        .onChange(of: Update(view: self)) { _, update in update.view.onChange(to: update.context, pipeline: update.pipeline) }
#else
        .onChange(of: Update(view: self)) { $0.view.onChange(to: $0.context, pipeline: $0.pipeline) }
#endif
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
        /// The value of ``LazyImage/reload(id:)``. Unlike the closures of the
        /// other modifiers, it's meant to trigger a change.
        let reloadID: AnyHashable?

        @MainActor
        init(view: LazyImage) {
            self.view = view
            self.context = view.overrides.applied(to: view.context)
            self.pipeline = view.resolvedPipeline
            self.reloadID = view.reloadID
        }

        static func == (lhs: Update, rhs: Update) -> Bool {
            lhs.context == rhs.context && lhs.pipeline === rhs.pipeline && lhs.reloadID == rhs.reloadID
        }
    }

    private func onAppear() {
        let context = overrides.applied(to: context)
        let pipeline = resolvedPipeline
        // Unless the disappear behavior is `.cancel`, the request keeps running
        // off screen, and restarting it would discard what it has downloaded.
        let isStillLoading = viewModel.isLoading && isLoaded(context, pipeline: pipeline)
        configure(pipeline: pipeline)
        // Undo the priority lowered by the `.lowerPriority` disappear behavior.
        viewModel.priority = context?.request.priority
        if !isStillLoading {
            viewModel.load(context?.request)
        }
    }

    private func onChange(to context: LazyImageContext?, pipeline: ImagePipeline) {
        let isAlreadyLoaded = isLoaded(context, pipeline: pipeline)
        // The view model has the ID of the last update that loaded: this action
        // only gets the new value on iOS 16.
        let isReloadRequested = viewModel.reloadID != reloadID
        configure(pipeline: pipeline)
        // Before the load, which would otherwise start with the priority of
        // the previous request. If it's only the priority that changed, this
        // is all there is to do.
        viewModel.priority = context?.request.priority
        if !isAlreadyLoaded || isReloadRequested {
            viewModel.load(context?.request)
        }
    }

    private func configure(pipeline: ImagePipeline) {
        viewModel.transaction = transaction
        viewModel.pipeline = pipeline
        viewModel.onStart = onStart
        viewModel.onCompletion = onCompletion
        viewModel.keepsPreviousImage = options?.value.keepsPreviousImage ?? false
        viewModel.animatesMemoryCacheHits = options?.value.animatesMemoryCacheHits ?? false
        viewModel.reloadID = reloadID
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

/// What the modifiers that few views use set.
private struct Options {
    var keepsPreviousImage = false
    var animatesMemoryCacheHits = false
    var reloadID: AnyHashable?
}

private final class Box<Value> {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

@MainActor @ViewBuilder
private func makeStateContent<Content: View>(_ makeContent: ((LazyImageState) -> Content)?, for state: LazyImageState) -> some View {
    if let makeContent {
        makeContent(state)
    } else {
        makeDefaultContent(for: state)
    }
}

@MainActor @ViewBuilder
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

/// Runs a transition by giving the content a new identity when a new image is
/// displayed.
private struct ImageTransitionModifier: ViewModifier {
    let container: ImageContainer?
    let transition: AnyTransition

    @State private var identity = DisplayedImageIdentity()

    func body(content: Content) -> some View {
        content
            .id(identity.update(with: container))
            .transition(transition)
    }
}

/// Tells when a new image takes the place of what is displayed. Comparing the
/// images wouldn't do: a final image continues its progressive previews.
final class DisplayedImageIdentity {
    private var container: ImageContainer?
    private var count = 0

    /// Returns the identity of the content that displays the given image. It
    /// can be called any number of times for an image.
    func update(with container: ImageContainer?) -> Int {
        guard let container else {
            self.container = nil
            return 0
        }
        if container.image !== self.container?.image, self.container?.isPreview != true {
            count &+= 1
        }
        self.container = container
        return count
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
    @State var attempt = 0

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
            .reload(id: attempt) // Example of how to implement retry

            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Button("Change Image") {
                    if url == URL(string: "https://kean.blog/images/pulse/01.png") {
                        url = URL(string: "https://kean.blog/images/pulse/02.png")
                    } else {
                        url = URL(string: "https://kean.blog/images/pulse/01.png")
                    }
                }
                Button("Retry") { attempt += 1 }
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
