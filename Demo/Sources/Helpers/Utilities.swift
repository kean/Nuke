// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

extension UIView {
    func pinToSuperview() {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: superview!.topAnchor),
            bottomAnchor.constraint(equalTo: superview!.bottomAnchor),
            leftAnchor.constraint(equalTo: superview!.leftAnchor),
            rightAnchor.constraint(equalTo: superview!.rightAnchor)
        ])
    }

    func centerInSuperview() {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: superview!.centerXAnchor),
            centerYAnchor.constraint(equalTo: superview!.centerYAnchor)
        ])
    }
}

// MARK: Core Image Integrations

/// Blurs image using CIGaussianBlur filter. Only blurs first scans of the
/// progressive JPEG.
struct _ProgressiveBlurImageProcessor: ImageProcessing, Hashable {
    func process(_ image: PlatformImage) -> PlatformImage? {
        return image
    }

    func process(_ container: ImageContainer, context: ImageProcessingContext) -> ImageContainer? {
        // CoreImage is too slow on simulator.
        #if targetEnvironment(simulator)
        return container
        #else
        guard !context.isFinal else {
            return container // No processing.
        }

        guard let scanNumber = container.userInfo[ImageDecoder.scanNumberKey] as? Int else {
            return container
        }

        // Blur partial images.
        if scanNumber < 5 {
            // Progressively reduce blur as we load more scans.
            let radius = max(2, 14 - scanNumber * 4)
            let filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius" : radius])
            return container.map {
                ImageProcessors.CoreImageFilter.apply(filter: filter, to: $0)
            }
        }

        // Scans 5+ are already good enough not to blur them.
        return container
        #endif
    }

    let identifier: String = "_ProgressiveBlurImageProcessor"

    var hashableIdentifier: AnyHashable {
        return self
    }
}

extension ImageContainer {
    /// Modifies the wrapped image and keeps all of the context.
    func map(_ closure: (PlatformImage) -> PlatformImage?) -> ImageContainer? {
        guard let image = closure(self.image) else {
            return nil
        }
        return ImageContainer(image: image, isPreview: isPreview, data: data, userInfo: userInfo)
    }
}
