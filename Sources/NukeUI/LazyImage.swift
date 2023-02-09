// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

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

    // Options
    private var makeContent: ((LazyImageState) -> Content)?
    private var animation: Animation? = .default
    private var processors: [any ImageProcessing]?
    private var priority: ImageRequest.Priority?
    private var pipeline: ImagePipeline = .shared
    private var onDisappearBehavior: DisappearBehavior? = .cancel

    // MARK: Initializers

#if !os(macOS)
    @available(*, deprecated, message: "The resizingMode is no longer supported. Please use one of the initializers that allows you to customize the displayed image directly.")
    public init(url: URL?, resizingMode: ImageResizingMode) where Content == Image {
        self.init(request: url.map { ImageRequest(url: $0) }, resizingMode: resizingMode)
    }

    @available(*, deprecated, message: "The resizingMode is no longer supported. Please use one of the initializers that allows you to customize the displayed image directly.")
    public init(request: ImageRequest?, resizingMode: ImageResizingMode) where Content == Image {
        self.init(request: request)
    }
#endif

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
        self.request = request.map(HashableRequest.init)
    }

    /// Loads and displays an image from the specified URL using a custom
    /// placeholder until the image loads.
    public init<I: View, P: View>(
        request: ImageRequest?,
        content: @escaping (Image) -> I,
        placeholder: @escaping () -> P
    ) where Content == _LazyImageContents<I, P> {
        self.request = request.map(HashableRequest.init)
        self.makeContent = { _LazyImageContents(state: $0, content: content, placeholder: placeholder) }
    }

    /// Loads and displays an image from the specified URL using a custom
    /// placeholder until the image loads.
    public init<I: View, P: View>(
        url: URL?,
        scale: CGFloat = 1,
        content: @escaping (Image) -> I,
        placeholder: @escaping () -> P
    ) where Content == _LazyImageContents<I, P> {
        self.request = url.map {
            HashableRequest(request: ImageRequest(url: $0, userInfo: [.scaleKey: scale]))
        }
        self.makeContent = { _LazyImageContents(state: $0, content: content, placeholder: placeholder) }
    }

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
        let state = LazyImageState(model)
        if let makeContent = makeContent {
            makeContent(state)
        } else {
            makeDefaultContent(for: state)
        }
    }

    @ViewBuilder private func makeDefaultContent(for state: LazyImageState) -> some View {
        if let image = state.image {
            image
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

public struct _LazyImageContents<I: View, P: View>: View {
    let state: LazyImageState
    let content: (SwiftUI.Image) -> I
    let placeholder: () -> P

    public var body: some View {
        if let image = state.image {
            content(image)
        } else {
            placeholder()
        }
    }
}
