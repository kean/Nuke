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
    ) -> Handle {
        let request: ImageRequest? = if let url { ImageRequest(url: url) } else { nil }
        return load(request, into: imageView, presentation: presentation, pipeline: pipeline)
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
    ///   - request: The image request. A `nil` request displays the failure
    ///   image.
    ///   - imageView: The image view to load the image into. It is held
    ///   weakly.
    ///   - presentation: The placeholder, the failure image, and the
    ///   transitions.
    ///   - pipeline: The pipeline to load the image with. `nil` keeps the
    ///   pipeline of the attached loader, ``ImagePipeline/shared`` by default.
    /// - returns: A handle to the load, to await its outcome or cancel it.
    @discardableResult
    public static func load(
        _ request: ImageRequest?,
        into imageView: _PlatformImageView,
        presentation: Presentation = Presentation(),
        pipeline: ImagePipeline? = nil
    ) -> Handle {
        load(request, into: imageView, pipeline: pipeline) { imageView, state in
            presentation.render(state, in: imageView)
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

// MARK: - Displaying

extension ImageLoader.Presentation {
    /// Displays the state in the image view: the placeholder while the image
    /// loads, the loaded image or a progressive preview with the
    /// ``transition``, or the failure image.
    ///
    /// ``ImageLoader/load(_:into:presentation:pipeline:)-(ImageRequest?,_,_,_)``
    /// calls it with every change of the state. To change something else
    /// along with the image, such as the content mode, call it from a closure
    /// of your own:
    ///
    /// ```swift
    /// let presentation = ImageLoader.Presentation(placeholder: UIImage(named: "placeholder"))
    ///
    /// ImageLoader.load(url, into: imageView) { imageView, state in
    ///     presentation.render(state, in: imageView)
    ///     imageView.contentMode = state.image == nil ? .center : .scaleAspectFill
    /// }
    /// ```
    @MainActor
    public func render(_ state: ImageLoader.State, in imageView: _PlatformImageView) {
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
            display(response.container, transition: transition, in: imageView)
        case let .finished(result, isSynchronous):
            if isSynchronous {
                removeAnimations(from: imageView)
            }
            render(result, isSynchronous: isSynchronous, state: state, in: imageView)
        case .reset:
            imageView.displayContainer(nil)
        case .progress, .cancelled:
            break
        }
    }
}

@MainActor
private extension ImageLoader.Presentation {
    func render(_ result: Result<ImageResponse, ImagePipeline.Error>, isSynchronous: Bool, state: ImageLoader.State, in imageView: _PlatformImageView) {
        switch result {
        case .success(let response):
            display(response.container, transition: isSynchronous ? nil : transition, in: imageView)
        case .failure:
            if let failureImage {
                let transition = isSynchronous ? nil : failureImageTransition
                display(ImageContainer(image: failureImage), transition: transition, in: imageView)
            } else if state.imageContainer == nil {
                displayPlaceholder(in: imageView)
            }
        }
    }

    func displayPlaceholder(in imageView: _PlatformImageView) {
        if let placeholder {
            imageView.displayContainer(ImageContainer(image: placeholder))
        } else {
            imageView.displayContainer(nil)
        }
    }

    func display(_ container: ImageContainer, transition: ImageLoader.Presentation.Transition?, in imageView: _PlatformImageView) {
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
    func removeAnimations(from imageView: _PlatformImageView) {
        imageView.layer?.removeAllAnimations()
    }

    func runFadeIn(_ container: ImageContainer, duration: TimeInterval, in imageView: _PlatformImageView) {
        imageView.displayContainer(container)
        imageView.layer?.animateOpacity(duration: duration)
    }
#else
    func removeAnimations(from imageView: _PlatformImageView) {
        imageView.layer.removeAllAnimations()
    }

    func runFadeIn(_ container: ImageContainer, duration: TimeInterval, in imageView: _PlatformImageView) {
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
