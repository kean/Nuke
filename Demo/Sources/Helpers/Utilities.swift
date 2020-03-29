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
    func process(image: UIImage, context: ImageProcessingContext?) -> UIImage? {
        // CoreImage is too slow on simulator.
        #if targetEnvironment(simulator)
        return image
        #else
        guard let context = context, !context.isFinal else {
            return image // No processing.
        }

        guard let scanNumber = context.scanNumber else {
            return image
        }

        // Blur partial images.
        if scanNumber < 5 {
            // Progressively reduce blur as we load more scans.
            let radius = max(2, 14 - scanNumber * 4)
            let filter = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius" : radius])
            return ImageProcessors.CoreImageFilter.apply(filter: filter, to: image)
        }

        // Scans 5+ are already good enough not to blur them.
        return image
        #endif
    }

    let identifier: String = "_ProgressiveBlurImageProcessor"

    var hashableIdentifier: AnyHashable {
        return self
    }
}
