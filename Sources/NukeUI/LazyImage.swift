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
    @StateObject private var viewModel = FetchImage()

    private let context: LazyImageContext?

    // Options
    private var makeContent: ((LazyImageState) -> Content)?
    private var animation: Animation?
    private var processors: [any ImageProcessing]?
    private var priority: ImageRequest.Priority?
    private var pipeline: ImagePipeline = .shared
    private var onDisappearBehavior: DisappearBehavior? = .cancel

    // MARK: Initializers

    /// Loads and displays an image using `SwiftUI.Image`.
    ///
    /// - Parameters:
    ///   - url: The image URL.
    public init(url: URL?, scale: CGFloat = 1) where Content == Image {
        self.init(request: url.map { ImageRequest(url: $0, userInfo: [.scaleKey: scale]) })
    }

    /// Loads and displays an image using `SwiftUI.Image`.
    ///
    /// - Parameters:
    ///   - request: The image request.
    public init(request: ImageRequest?) where Content == Image {
        self.context = request.map(LazyImageContext.init)
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
        self.context = request.map { LazyImageContext(request: $0) }
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
        .onChange(of: context, perform: { load($0) })
    }

    @ViewBuilder private var content: some View {
        let state = LazyImageState(viewModel: viewModel)
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
        load(context)
    }

    private func load(_ request: LazyImageContext?) {
        viewModel.animation = animation
        viewModel.processors = processors ?? []
        viewModel.priority = priority
        viewModel.pipeline = pipeline

        viewModel.load(request?.request)
    }

    private func onDisappear() {
        guard let behavior = onDisappearBehavior else { return }
        switch behavior {
        case .cancel: viewModel.cancel()
        case .lowerPriority: viewModel.priority = .veryLow
        }
    }

    private func map(_ closure: (inout LazyImage) -> Void) -> Self {
        var copy = self
        closure(&copy)
        return copy
    }
}

private struct LazyImageContext: Equatable {
    let request: ImageRequest

    static func == (lhs: LazyImageContext, rhs: LazyImageContext) -> Bool {
        let lhs = lhs.request
        let rhs = rhs.request
        return lhs.imageId == rhs.imageId &&
        lhs.priority == rhs.priority &&
        lhs.options == rhs.options
    }
}

#if DEBUG
@available(iOS 15, tvOS 15, macOS 12, watchOS 8, *)
struct LazyImage_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LazyImage(url: URL(string: "https://kean.blog/images/pulse/01.png"))
                .previewDisplayName("LazyImage")

            LazyImageDemoView()
                .previewDisplayName("Resizable")

            AsyncImage(url: URL(string: "https://kean.blog/images/pulse/01.png"))
                .previewDisplayName("AsyncImage")
        }
    }
}

// This demonstrates that the view reacts correctly to the URL changes.
@available(iOS 14, tvOS 14, macOS 11, watchOS 7, *)
private struct LazyImageDemoView: View {
    @State var url = URL(string: "https://kean.blog/images/pulse/01.png")

    var body: some View {
        VStack {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
                }
            }
            Button("Next Image") {
                url = URL(string: "https://kean.blog/images/pulse/02.png")
            }
        }
    }
}
#endif
