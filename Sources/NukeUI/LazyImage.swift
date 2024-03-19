// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import SwiftUI
import Combine

public typealias ImageRequest = Nuke.ImageRequest

/// A view that asynchronously loads and displays an image.
///
/// ``LazyImage`` is designed to be similar to the native [`AsyncImage`](https://developer.apple.com/documentation/SwiftUI/AsyncImage),
/// but it uses [Nuke](https://github.com/kean/Nuke) for loading images. You
/// can take advantage of all of its features, such as caching, prefetching,
/// task coalescing, smart background decompression, request priorities, and more.
@MainActor
@available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 10.16, *)
public struct LazyImage<Content: View, Placeholder: View>: View {
    @StateObject private var viewModel = FetchImage()

    private var context: LazyImageContext?
    private var makeContent: ((LazyImageState) -> Content)?
    private var transaction: Transaction
    private var pipeline: ImagePipeline = .shared
    private var onStart: ((ImageTask) -> Void)?
    private var onDisappearBehavior: DisappearBehavior? = .cancel
    private var onCompletion: ((Result<ImageResponse, Error>) -> Void)?
    private let placeholder: () -> Placeholder

    // MARK: Initializers

    /// Loads and displays an image using `SwiftUI.Image`.
    ///
    /// - Parameters:
    ///   - url: The image URL.
    ///   - placeholder: Optional placeholder, defaults to `Color(.secondarySystemBackground)`
    public init(url: URL?, placeholder: @escaping () -> Placeholder = { Color(.secondarySystemBackground) }) where Content == Image {
        self.init(request: url.map { ImageRequest(url: $0) }, placeholder: placeholder)
    }

    /// Loads and displays an image using `SwiftUI.Image`.
    ///
    /// - Parameters:
    ///   - request: The image request.
    ///   - placeholder: Optional placeholder, defaults to `Color(.secondarySystemBackground)`
    public init(request: ImageRequest?, placeholder: @escaping () -> Placeholder = { Color(.secondarySystemBackground) }) where Content == Image {
        self.context = request.map(LazyImageContext.init)
        self.transaction = Transaction(animation: nil)
        self.placeholder = placeholder
    }

    /// Loads an images and displays custom content for each state.
    ///
    /// See also ``init(request:transaction:content:)``
    public init(url: URL?,
                transaction: Transaction = Transaction(animation: nil),
                placeholder: @escaping () -> Placeholder = { Color(.secondarySystemBackground) },
                @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.init(request: url.map { ImageRequest(url: $0) }, 
                  transaction: transaction,
                  placeholder: placeholder,
                  content: content)
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
    public init(request: ImageRequest?,
                transaction: Transaction = Transaction(animation: nil),
                placeholder: @escaping () -> Placeholder,
                @ViewBuilder content: @escaping (LazyImageState) -> Content) {
        self.context = request.map { LazyImageContext(request: $0) }
        self.transaction = transaction
        self.placeholder = placeholder
        self.makeContent = content
    }

    // MARK: Options

    /// Sets processors to be applied to the image.
    ///
    /// If you pass an image requests with a non-empty list of processors as
    /// a source, your processors will be applied instead.
    public func processors(_ processors: [any ImageProcessing]?) -> Self {
        map { $0.context?.request.processors = processors ?? [] }
    }

    /// Sets the priority of the requests.
    public func priority(_ priority: ImageRequest.Priority?) -> Self {
        map { $0.context?.request.priority = priority ?? .normal }
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

    /// Gets called when the request is started.
    public func onStart(_ closure: @escaping (ImageTask) -> Void) -> Self {
        map { $0.viewModel.onStart = closure }
    }

    /// Override the behavior on disappear. By default, the view is reset.
    public func onDisappear(_ behavior: DisappearBehavior?) -> Self {
        map { $0.onDisappearBehavior = behavior }
    }

    /// Gets called when the current request is completed.
    public func onCompletion(_ closure: @escaping (Result<ImageResponse, Error>) -> Void) -> Self {
        map { $0.onCompletion = closure }
    }

    private func map(_ closure: (inout LazyImage) -> Void) -> Self {
        var copy = self
        closure(&copy)
        return copy
    }

    // MARK: Body

    public var body: some View {
        ZStack {
            if let makeContent {
                makeContent(viewModel)
            } else {
                makeDefaultContent(for: viewModel)
            }
        }
        .onAppear { onAppear() }
        .onDisappear { onDisappear() }
        .onChange(of: context) {
            viewModel.load($0?.request)
        }
    }

    @ViewBuilder
    private func makeDefaultContent(for state: LazyImageState) -> some View {
        if let image = state.image {
            image
        } else {
            placeholder()
        }
    }

    private func onAppear() {
        viewModel.transaction = transaction
        viewModel.pipeline = pipeline
        viewModel.onStart = onStart
        viewModel.onCompletion = onCompletion
        viewModel.load(context?.request)
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

private struct LazyImageContext: Equatable {
    var request: ImageRequest

    static func == (lhs: LazyImageContext, rhs: LazyImageContext) -> Bool {
        let lhs = lhs.request
        let rhs = rhs.request
        return lhs.preferredImageId == rhs.preferredImageId &&
        lhs.priority == rhs.priority &&
        lhs.processors == rhs.processors &&
        lhs.priority == rhs.priority &&
        lhs.options == rhs.options
    }
}

#if DEBUG
@available(iOS 15, tvOS 15, macOS 12, watchOS 8, *)
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
@available(iOS 15, tvOS 15, macOS 12, watchOS 8, *)
private struct LazyImageDemoView: View {
    @State var url = URL(string: "https://kean.blog/images/pulse/01.png")
    @State var isBlured = false
    @State var imageViewId = UUID()

    var body: some View {
        VStack {
            Spacer()

            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().aspectRatio(contentMode: .fit)
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
