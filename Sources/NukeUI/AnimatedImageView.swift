// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

#if (os(iOS) || os(tvOS)) && !targetEnvironment(macCatalyst)
import UIKit

@MainActor
public final class AnimatedImageView: UIImageView, GIFAnimatable {
    /// A lazy animator.
    lazy var animator: Animator? = {
        return Animator(withDelegate: self)
    }()

    /// Layer delegate method called periodically by the layer. **Should not** be called manually.
    ///
    /// - parameter layer: The delegated layer.
    override public func display(_ layer: CALayer) {
        if UIImageView.instancesRespond(to: #selector(display(_:))) {
            super.display(layer)
        }
        updateImageIfNeeded()
    }
}
#endif
