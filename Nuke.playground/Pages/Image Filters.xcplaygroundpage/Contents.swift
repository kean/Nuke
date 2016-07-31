import Nuke
import UIKit
import XCPlayground

/*:
### Applying Filters
Applying image filters is as easy as setting `processor` property on the `Request`. Nuke does all the heavy lifting, including storing processed images into memory cache. Creating image filters is also dead simple thanks to `Processing` protocol and its extensions.
*/

class ImageFilterDrawInCircle: Processing {
    func process(image: UIImage) -> UIImage? {
        return drawImageInCircle(cropImageToSquare(image))
    }
}

example("Applying Filters") {
    var request = Request(url: NSURL(string: "https://farm4.staticflickr.com/3803/14287618563_b21710bd8c_z_d.jpg")!)
    request.processor = ImageFilterDrawInCircle()
    
    Nuke.task(with: request) {
        let image = $0.image
    }.resume()
}

/*:
### Creating CoreImage Based Filters
 Here we use a simple function `applyFilter` to wrap a `CIGaussianBlur` into an `Processing` protocol.
 */

/// Blurs image using CIGaussianBlur filter.
public struct ImageFilterGaussianBlur: Processing {
    /// Blur radius.
    public let radius: Int
    
    /**
     Initializes the receiver with a blur radius.
     
     - parameter radius: Blur radius, default value is 8.
     */
    public init(radius: Int = 8) {
        self.radius = radius
    }
    
    /// Applies CIGaussianBlur filter to the image.
    public func process(image: UIImage) -> UIImage? {
        return image.applyFilter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : radius]))
    }
}

/// Compares two filters based on their radius.
public func ==(lhs: ImageFilterGaussianBlur, rhs: ImageFilterGaussianBlur) -> Bool {
    return lhs.radius == rhs.radius
}

/*:
### Composing Filters
It's easy to combine multiple filters using `ImageFilterComposition` class. Lets use a `ImageFilterDrawInCircle` from the previous example and combine it with a gaussian blur filter.
*/

import CoreImage

example("Composing Filters") {
    var request = Request(url: NSURL(string: "https://farm4.staticflickr.com/3803/14287618563_b21710bd8c_z_d.jpg")!)
    
    // Compose filters
    let filter = ProcessorComposition(processors: [ ImageFilterGaussianBlur(), ImageFilterDrawInCircle()])
    request.processor = filter

    Nuke.task(with: request) {
        let image = $0.image
    }.resume()
}

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true

//: [Next](@ne
