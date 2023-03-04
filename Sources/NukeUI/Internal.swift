// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

import SwiftUI
import Nuke

#if os(macOS)
public typealias _PlatformBaseView = NSView
typealias _PlatformImageView = NSImageView
typealias _PlatformColor = NSColor
#else
public typealias _PlatformBaseView = UIView
typealias _PlatformImageView = UIImageView
typealias _PlatformColor = UIColor
#endif

extension _PlatformBaseView {
    @discardableResult
    func pinToSuperview() -> [NSLayoutConstraint] {
        translatesAutoresizingMaskIntoConstraints = false
        let constraints = [
            topAnchor.constraint(equalTo: superview!.topAnchor),
            bottomAnchor.constraint(equalTo: superview!.bottomAnchor),
            leftAnchor.constraint(equalTo: superview!.leftAnchor),
            rightAnchor.constraint(equalTo: superview!.rightAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    @discardableResult
    func centerInSuperview() -> [NSLayoutConstraint] {
        translatesAutoresizingMaskIntoConstraints = false
        let constraints = [
            centerXAnchor.constraint(equalTo: superview!.centerXAnchor),
            centerYAnchor.constraint(equalTo: superview!.centerYAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    @discardableResult
    func layout(with position: LazyImageView.SubviewPosition) -> [NSLayoutConstraint] {
        switch position {
        case .center: return centerInSuperview()
        case .fill: return pinToSuperview()
        }
    }
}

extension CALayer {
    func animateOpacity(duration: CFTimeInterval) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = duration
        animation.fromValue = 0
        animation.toValue = 1
        add(animation, forKey: "imageTransition")
    }
}

#if os(macOS)
extension NSView {
    func setNeedsUpdateConstraints() {
        needsUpdateConstraints = true
    }

    func insertSubview(_ subivew: NSView, at index: Int) {
        addSubview(subivew, positioned: .below, relativeTo: subviews.first)
    }
}

extension NSColor {
    static var secondarySystemBackground: NSColor {
        .controlBackgroundColor // Close-enough, but we should define a custom color
    }
}
#endif

#endif

#if os(tvOS) || os(watchOS)
import UIKit

extension UIColor {
    static var secondarySystemBackground: UIColor {
        lightGray.withAlphaComponent(0.5)
    }
}
#endif

func == (lhs: [any ImageProcessing], rhs: [any ImageProcessing]) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }
    // Lazily creates `hashableIdentifiers` because for some processors the
    // identifiers might be expensive to compute.
    return zip(lhs, rhs).allSatisfy {
        $0.hashableIdentifier == $1.hashableIdentifier
    }
}

extension ImageRequest {
    var preferredImageId: String {
        if !userInfo.isEmpty, let imageId = userInfo[.imageIdKey] as? String {
            return imageId
        }
        return imageId ?? ""
    }
}
