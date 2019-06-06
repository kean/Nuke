// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

extension UIView {
    func pinToSuperview() {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(
            [topAnchor.constraint(equalTo: superview!.topAnchor),
             bottomAnchor.constraint(equalTo: superview!.bottomAnchor),
             leftAnchor.constraint(equalTo: superview!.leftAnchor),
             rightAnchor.constraint(equalTo: superview!.rightAnchor)]
        )

    }

    func centerInSuperview() {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(
            [centerXAnchor.constraint(equalTo: superview!.centerXAnchor),
             centerYAnchor.constraint(equalTo: superview!.centerYAnchor)]
        )
    }
}

// MARK: Core Image Integrations

let sharedCIContext = CIContext()

extension UIImage {
    func applyFilter(context: CIContext = sharedCIContext, closure: (CoreImage.CIImage) -> CoreImage.CIImage?) -> UIImage? {
        func inputImageForImage(_ image: Image) -> CoreImage.CIImage? {
            if let image = image.cgImage {
                return CoreImage.CIImage(cgImage: image)
            }
            if let image = image.ciImage {
                return image
            }
            return nil
        }
        guard let inputImage = inputImageForImage(self),
            let outputImage = closure(inputImage) else {
            return nil
        }
        guard let imageRef = context.createCGImage(outputImage, from: inputImage.extent) else {
            return nil
        }
        return UIImage(cgImage: imageRef, scale: self.scale, orientation: self.imageOrientation)
    }

    func applyFilter(filter: CIFilter?, context: CIContext = sharedCIContext) -> UIImage? {
        guard let filter = filter else {
            return nil
        }
        return applyFilter(context: context) {
            filter.setValue($0, forKey: kCIInputImageKey)
            return filter.outputImage
        }
    }
}

/// Blurs image using CIGaussianBlur filter. Only blurs first scans of the
/// progressive JPEG.
struct _ProgressiveBlurImageProcessor: ImageProcessing, Hashable {
    func process(image: Image, context: ImageProcessingContext?) -> Image? {
        // CoreImage is too slow on simulator.
        #if targetEnvironment(simulator)
        return image
        #else
        guard !context.isFinal else {
            return image // No processing.
        }

        guard let scanNumber = context.scanNumber else {
            return image
        }

        // Blur partial images.
        if scanNumber < 5 {
            // Progressively reduce blur as we load more scans.
            let radius = max(2, 14 - scanNumber * 4)
            return image.applyFilter(filter: CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius" : radius]))
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
