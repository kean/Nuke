// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

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

/// Blurs image using CIGaussianBlur filter.
struct GaussianBlur: ImageProcessing {
    private let radius: Int

    /// Initializes the receiver with a blur radius.
    init(radius: Int = 8) {
        self.radius = radius
    }

    /// Applies CIGaussianBlur filter to the image.
    func process(_ image: UIImage) -> UIImage? {
        return image.applyFilter(filter: CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : radius]))
    }

    /// Compares two filters based on their radius.
    static func ==(lhs: GaussianBlur, rhs: GaussianBlur) -> Bool {
        return lhs.radius == rhs.radius
    }
}
