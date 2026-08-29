// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import ImageIO
import SwiftUI
import UIKit

/// Displays an animated image (GIF or APNG).
///
/// Nuke decodes the first frame of an animated image and passes the original
/// data along in ``ImageContainer/data`` – everything an animated image view
/// needs. This one uses ImageIO, which decodes the frames lazily instead of
/// keeping every bitmap in memory.
final class AnimatedImageView: UIImageView {
    var data: Data? {
        didSet {
            guard data != oldValue else { return }
            startAnimating(with: data)
        }
    }

    /// Invalidates the block of the previous animation.
    private var generation = 0

    private func startAnimating(with data: Data?) {
        generation &+= 1
        image = nil
        guard let data else { return }

        let generation = generation
        // ImageIO calls the block on the main queue at the intervals defined
        // by the frame delays of the image. The block holds a weak reference
        // to the view and stops as soon as the view is gone.
        CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, frame, stop in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else {
                    stop.pointee = true
                    return
                }
                self.image = UIImage(cgImage: frame)
            }
        }
    }
}

/// Displays an animated image in SwiftUI.
struct AnimatedImage: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> AnimatedImageView {
        let view = AnimatedImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: AnimatedImageView, context: Context) {
        view.data = data
    }
}
