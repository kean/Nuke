// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import SwiftUI
import Combine

public typealias ImageRequest = Nuke.ImageRequest
public typealias ImageResponse = Nuke.ImageResponse
public typealias ImagePipeline = Nuke.ImagePipeline
public typealias ImageContainer = Nuke.ImageContainer

/// Lazily loads and displays images.
///
/// ``LazyImage`` is designed similar to the native [`AsyncImage`](https://developer.apple.com/documentation/SwiftUI/AsyncImage),
/// but it uses [Nuke](https://github.com/kean/Nuke) for loading images so you
/// can take advantage of all of its features, such as caching, prefetching,
/// task coalescing, smart background decompression, request priorities, and more.
@MainActor
@available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 10.16, *)
public struct LazyImage<Content: View>: View {
    @StateObject private var model = FetchImage()

    private let request: HashableRequest?

#if !os(watchOS)
    private var onCreated: ((ImageView) -> Void)?
#endif

    // Options
    private var makeContent: ((LazyImageState) -> Content)?
    private var animation: Animation? = .default
    private var processors: [any ImageProcessing]?
    private var priority: ImageRequest.Priority?
    private var pipeline: ImagePipeline = .shared
    private var onDisappearBehavior: DisappearBehavior? = .cancel
    private var onStart: ((ImageTask) -> Void)?
    private var onPreview: ((ImageResponse) -> Void)?
    private var onProgress: ((ImageTask.Progress) -> Void)?
    private var onSuccess: ((ImageResponse) -> Void)?
    private var onFailure: ((Error) -> Void)?
    private var onCompletion: ((Result<ImageResponse, Error>) -> Void)?
    private var resizingMode: ImageResizingMode?

    // MARK: Initializers

#if !os(macOS)
    /// Loads and displays an image using ``Image``.
    ///
    /// - Parameters:
    ///   - url: The image URL.
    ///   - resizingMode: The displayed image resizing mode.
    public init(url: URL?, resizingMode: ImageResizingMode = .aspectFill) where Content == Image {
        self.init(request: url.map { ImageRequest(url: $0) }, resizingMode: resizingMode)
    }

    /// Loads and displays an image using ``Image``.
    ///
    /// - Parameters:
    ///   - request: The image request.
    ///   - resizingMode: The displayed image resizing mode.
    public init(request: ImageRequest?, resizingMode: ImageResizingMode = .aspectFill) where Content == Image {
        self.request = request.map { HashableRequest(request: $0) }
        self.resizingMode = resizingMode
    }

    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use init(request:) or init(url).")
    public init(source: (any ImageRequestConvertible)?, resizingMode: ImageResizingMode = .aspectFill) where Content == Image {
        self.init(request: source?.asImageRequest(), resizingMode: resizingMode)
    }
#else
    /// Loads and displays an image using ``Image``.
    ///
    /// - Parameters:
    ///   - url: The image URL.
    public init(url: URL?) where Content == Image {
        self.init(request: url.map { ImageRequest(url: $0) })
    }

    /// Loads and displays an image using ``Image``.
    ///
    /// - Parameters:
    ///   - request: The image request.
    public init(request: ImageRequest?) where Content == Image {
        self.request = request.map { HashableRequest(request: $0) }
    }

    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use init(request:) or init(url).")
    public init(source: (any ImageRequestConvertible)?) where Content == Image {
        self.request = source.map { HashableRequest(request: $0.asImageRequest()) }
    }
#endif
    /// Loads an images and displays custom content for each state.
    ///
    /// See also ``init(request:content:)``
    public init(url: URL?, @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.init(request: url.map { ImageRequest(url: $0) }, content: content)
    }

    /// Loads an images and displays custom content for each state.
    ///
    /// - Parameters:
    ///   - request: The image request.
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
    public init(request: ImageRequest?, @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.request = request.map { HashableRequest(request: $0) }
        self.makeContent = content
    }

    // Deprecated in Nuke 11.0
    @available(*, deprecated, message: "Please use init(request:) or init(url).")
    public init(source: (any ImageRequestConvertible)?, @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.request = source.map { HashableRequest(request: $0.asImageRequest()) }
        self.makeContent = content
    }

    // MARK: Animation

    /// Animations to be used when displaying the loaded images. By default, `.default`.
    ///
    /// - note: Animation isn't used when image is available in memory cache.
    public func animation(_ animation: Animation?) -> Self {
        map { $0.animation = animation }
    }

    // MARK: Managing Image Tasks

    /// Sets processors to be applied to the image.
    ///
    /// If you pass an image requests with a non-empty list of processors as
    /// a source, your processors will be applied instead.
    public func processors(_ processors: [any ImageProcessing]?) -> Self {
        map { $0.processors = processors }
    }

    /// Sets the priority of the requests.
    public func priority(_ priority: ImageRequest.Priority?) -> Self {
        map { $0.priority = priority }
    }

    /// Changes the underlying pipeline used for image loading.
    public func pipeline(_ pipeline: ImagePipeline) -> Self {
        map { $0.pipeline = pipeline }
    }

    public enum DisappearBehavior {
        /// Cancels the current request but keeps the presentation state of
        /// the already displayed image.
        case cancel
        /// Lowers the request's priority to very low
        case lowerPriority
    }

    /// Override the behavior on disappear. By default, the view is reset.
    public func onDisappear(_ behavior: DisappearBehavior?) -> Self {
        map { $0.onDisappearBehavior = behavior }
    }

    // MARK: Callbacks

    /// Gets called when the request is started.
    public func onStart(_ closure: @escaping (ImageTask) -> Void) -> Self {
        map { $0.onStart = closure }
    }

    /// Gets called when the request progress is updated.
    public func onPreview(_ closure: @escaping (ImageResponse) -> Void) -> Self {
        map { $0.onPreview = closure }
    }

    /// Gets called when the request progress is updated.
    public func onProgress(_ closure: @escaping (ImageTask.Progress) -> Void) -> Self {
        map { $0.onProgress = closure }
    }

    /// Gets called when the requests finished successfully.
    public func onSuccess(_ closure: @escaping (ImageResponse) -> Void) -> Self {
        map { $0.onSuccess = closure }
    }

    /// Gets called when the requests fails.
    public func onFailure(_ closure: @escaping (Error) -> Void) -> Self {
        map { $0.onFailure = closure }
    }

    /// Gets called when the request is completed.
    public func onCompletion(_ closure: @escaping (Result<ImageResponse, Error>) -> Void) -> Self {
        map { $0.onCompletion = closure }
    }

#if !os(watchOS)

    /// Returns an underlying image view.
    ///
    /// - parameter configure: A closure that gets called once when the view is
    /// created and allows you to configure it based on your needs.
    public func onCreated(_ configure: ((ImageView) -> Void)?) -> Self {
        map { $0.onCreated = configure }
    }
#endif

    // MARK: Body

    public var body: some View {
        // Using ZStack to add an identity to the view to prevent onAppear from
        // getting called whenever the content changes.
        ZStack {
            content
        }
        .onAppear(perform: { onAppear() })
        .onDisappear(perform: { onDisappear() })
        .onChange(of: request, perform: { load($0) })
    }

    @ViewBuilder private var content: some View {
        if let makeContent = makeContent {
            makeContent(LazyImageState(model))
        } else {
            makeDefaultContent()
        }
    }

    @ViewBuilder private func makeDefaultContent() -> some View {
        if let imageContainer = model.imageContainer {
#if os(watchOS)
            switch resizingMode ?? ImageResizingMode.aspectFill {
            case .aspectFit, .aspectFill:
                model.view?
                    .resizable()
                    .aspectRatio(contentMode: resizingMode == .aspectFit ? .fit : .fill)
            case .fill:
                model.view?
                    .resizable()
            default:
                model.view
            }
#else
            Image(imageContainer) {
#if os(iOS) || os(tvOS)
                if let resizingMode = self.resizingMode {
                    $0.resizingMode = resizingMode
                }
#endif
                onCreated?($0)
            }
#endif
        } else {
            Rectangle().foregroundColor(Color(.secondarySystemBackground))
        }
    }

    private func onAppear() {
        // Unfortunately, you can't modify @State directly in the properties
        // that set these options.
        model.animation = animation
        if let processors = processors { model.processors = processors }
        if let priority = priority { model.priority = priority }
        model.pipeline = pipeline
        model.onStart = onStart
        model.onPreview = onPreview
        model.onProgress = onProgress
        model.onSuccess = onSuccess
        model.onFailure = onFailure
        model.onCompletion = onCompletion

        load(request)
    }

    private func load(_ request: HashableRequest?) {
        model.load(request?.request)
    }

    private func onDisappear() {
        guard let behavior = onDisappearBehavior else { return }
        switch behavior {
        case .cancel: model.cancel()
        case .lowerPriority: model.priority = .veryLow
        }
    }

    private func map(_ closure: (inout LazyImage) -> Void) -> Self {
        var copy = self
        closure(&copy)
        return copy
    }
}

public enum ImageResizingMode {
    case fill
    case aspectFit
    case aspectFill
    case center
    case top
    case bottom
    case left
    case right
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

private struct HashableRequest: Hashable {
    let request: ImageRequest

    func hash(into hasher: inout Hasher) {
        hasher.combine(request.imageId)
        hasher.combine(request.options)
        hasher.combine(request.priority)
    }

    static func == (lhs: HashableRequest, rhs: HashableRequest) -> Bool {
        let lhs = lhs.request
        let rhs = rhs.request
        return lhs.imageId == rhs.imageId &&
        lhs.priority == rhs.priority &&
        lhs.options == rhs.options
    }
}
