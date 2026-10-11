// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension ImageLoader {
    /// Loads an image with the given URL into the image view.
    ///
    /// See ``load(_:into:presentation:pipeline:)-(ImageRequest?,_,_,_)``.
    @discardableResult
    public static func load(
        _ url: URL?,
        into imageView: _PlatformImageView,
        presentation: Presentation = Presentation(),
        pipeline: ImagePipeline? = nil
    ) -> Load {
        load(url.map { ImageRequest(url: $0) }, into: imageView, presentation: presentation, pipeline: pipeline)
    }

    /// Loads an image with the given request into the image view.
    ///
    /// The image view displays the placeholder while the image loads, the
    /// loaded image, or the failure image, as described by the
    /// `presentation`. An image found in the memory cache is displayed before
    /// this method returns. An ``AnimatedImageView`` plays the animated images.
    ///
    /// ```swift
    /// ImageLoader.load(url, into: imageView, presentation: .init(
    ///     placeholder: UIImage(named: "placeholder"),
    ///     transition: .fadeIn(duration: 0.33)
    /// ))
    /// ```
    ///
    /// The load uses the loader attached to the image view (see
    /// ``loader(for:)``), so it cancels the previous load into the same view.
    ///
    /// - parameters:
    ///   - pipeline: The pipeline to load the image with. `nil` keeps the
    ///   pipeline of the attached loader, ``ImagePipeline/shared`` by default.
    /// - returns: The load, which can be awaited for its outcome.
    @discardableResult
    public static func load(
        _ request: ImageRequest?,
        into imageView: _PlatformImageView,
        presentation: Presentation = Presentation(),
        pipeline: ImagePipeline? = nil
    ) -> Load {
        let presenter = ImageViewPresenter(presentation: presentation)
        return load(request, into: imageView, pipeline: pipeline) { imageView, state in
            presenter.render(state, in: imageView)
        }
    }
}

// MARK: - Presentation

extension ImageLoader {
    /// How an image view displays a load.
    public struct Presentation: Sendable {
        /// The image to display while the image loads. `nil` by default, which
        /// clears the image view.
        public var placeholder: PlatformImage?

        /// The image to display when the load fails. `nil` by default, which
        /// keeps the placeholder.
        public var failureImage: PlatformImage?

        /// The transition to run when a loaded image or a progressive preview
        /// is displayed. It doesn't run for an image found in the memory cache.
        /// `nil` by default.
        public var transition: Transition?

        /// The transition to run when the failure image is displayed. `nil` by
        /// default.
        public var failureImageTransition: Transition?

        /// Creates a presentation.
        public init(
            placeholder: PlatformImage? = nil,
            transition: Transition? = nil,
            failureImage: PlatformImage? = nil,
            failureImageTransition: Transition? = nil
        ) {
            self.placeholder = placeholder
            self.transition = transition
            self.failureImage = failureImage
            self.failureImageTransition = failureImageTransition
        }

        /// An animated image transition.
        public struct Transition: Sendable {
            let style: ImageViewTransitionStyle

            /// A cross-dissolve from the image that is displayed.
            public static func fadeIn(duration: TimeInterval) -> Transition {
                Transition(style: .fadeIn(duration: duration))
            }

            /// A custom transition. The closure displays the image, and
            /// animates it.
            public static func custom(_ closure: @escaping @MainActor @Sendable (_PlatformImageView, ImageContainer) -> Void) -> Transition {
                Transition(style: .custom(closure))
            }
        }
    }
}

enum ImageViewTransitionStyle: Sendable {
    case fadeIn(duration: TimeInterval)
    case custom(@MainActor @Sendable (_PlatformImageView, ImageContainer) -> Void)
}

// MARK: - ImageViewPresenter

/// Displays the states of a load in an image view.
@MainActor
private final class ImageViewPresenter {
    private let presentation: ImageLoader.Presentation

    init(presentation: ImageLoader.Presentation) {
        self.presentation = presentation
    }

    func render(_ state: ImageLoader.State, in imageView: _PlatformImageView) {
        switch state.event {
        case .started:
            removeAnimations(from: imageView)
            guard !state.isPreviousImage else {
                return // Keeps displaying it until the new load has an image
            }
            if let container = state.imageContainer {
                imageView.displayContainer(container) // A preview found in the memory cache
            } else {
                displayPlaceholder(in: imageView)
            }
        case .preview(let response):
            display(response.container, transition: presentation.transition, in: imageView)
        case let .finished(result, isSync):
            if isSync {
                removeAnimations(from: imageView)
            }
            render(result, isSync: isSync, state: state, in: imageView)
        case .reset:
            imageView.displayContainer(nil)
        case .progress, .cancelled:
            break
        }
    }

    private func render(_ result: Result<ImageResponse, ImagePipeline.Error>, isSync: Bool, state: ImageLoader.State, in imageView: _PlatformImageView) {
        switch result {
        case .success(let response):
            display(response.container, transition: isSync ? nil : presentation.transition, in: imageView)
        case .failure:
            if let failureImage = presentation.failureImage {
                let transition = isSync ? nil : presentation.failureImageTransition
                display(ImageContainer(image: failureImage), transition: transition, in: imageView)
            } else if state.imageContainer == nil {
                displayPlaceholder(in: imageView)
            }
        }
    }

    private func displayPlaceholder(in imageView: _PlatformImageView) {
        imageView.displayContainer(presentation.placeholder.map { ImageContainer(image: $0) })
    }

    private func display(_ container: ImageContainer, transition: ImageLoader.Presentation.Transition?, in imageView: _PlatformImageView) {
        guard let transition else {
            imageView.displayContainer(container)
            return
        }
        switch transition.style {
        case .fadeIn(let duration):
            runFadeIn(container, duration: duration, in: imageView)
        case .custom(let closure):
            closure(imageView, container)
        }
    }

#if os(macOS)
    private func removeAnimations(from imageView: _PlatformImageView) {
        imageView.layer?.removeAllAnimations()
    }

    private func runFadeIn(_ container: ImageContainer, duration: TimeInterval, in imageView: _PlatformImageView) {
        imageView.displayContainer(container)
        imageView.layer?.animateOpacity(duration: duration)
    }
#else
    private func removeAnimations(from imageView: _PlatformImageView) {
        imageView.layer.removeAllAnimations()
    }

    private func runFadeIn(_ container: ImageContainer, duration: TimeInterval, in imageView: _PlatformImageView) {
        UIView.transition(
            with: imageView,
            duration: duration,
            options: [.transitionCrossDissolve, .allowUserInteraction],
            animations: { imageView.displayContainer(container) }
        )
    }
#endif
}

#endif
