import Nuke
import UIKit
import XCPlayground

/*:
### Applying Filters
Applying image filters is as easy as calling `process` method on the `Request`. Nuke does all the heavy lifting, including storing processed images into memory cache.
 
You can specify custom image processors using `Processing` protocol which consists of a single method `process(image: Image) -> Image?`.
*/

class DrawInCircle: Processing {
    func process(_ image: Image) -> Image? {
        return drawImageInCircle(cropImageToSquare(image))
    }
    
    static func ==(lhs: DrawInCircle, rhs: DrawInCircle) -> Bool {
        return true
    }
}

example("Applying Filters") {
    let request = Request(url: URL(string: "https://farm4.staticflickr.com/3803/14287618563_b21710bd8c_z_d.jpg")!).process(with: DrawInCircle())
    
    Nuke.Loader.shared.loadImage(with: request, token: nil).then {
        let image = $0
    }
}

/*:
### Creating CoreImage Based Filters
 Here we use a simple function `applyFilter` to wrap a `CIGaussianBlur` into an `Processing` protocol.
 */

/// Blurs image using CIGaussianBlur filter.
struct GaussianBlur: Processing {
    /// Blur radius.
    let radius: Int = 8
    
    /// Applies CIGaussianBlur filter to the image.
    func process(_ image: Image) -> Image? {
        return image.applyFilter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : radius]))
    }
    
    static func ==(lhs: GaussianBlur, rhs: GaussianBlur) -> Bool {
        return lhs.radius == rhs.radius
    }
}

/*:
### Composing Filters
It's easy to combine multiple filters. Lets use a `ImageFilterDrawInCircle` from the previous example and combine it with a gaussian blur filter.
*/

import CoreImage

example("Composing Filters") {
    let request = Request(url: URL(string: "https://farm4.staticflickr.com/3803/14287618563_b21710bd8c_z_d.jpg")!)
        .process(with: GaussianBlur()).process(with: DrawInCircle())
    
    Nuke.Loader.shared.loadImage(with: request, token: nil).then {
        let image = $0
    }
}

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true

//: [Next](@ne
