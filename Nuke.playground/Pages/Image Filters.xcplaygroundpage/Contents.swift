import Nuke
import UIKit
import XCPlayground

/*:
### Applying Filters
Applying image filters is as easy as setting `processor` property on the `ImageRequest`. Nuke does all the heavy lifting, including storing processed images into memory cache. Creating image filters is also dead simple thanks to `ImageProcessing` protocol and its extensions.
*/

class ImageFilterDrawInCircle: ImageProcessing {
    func process(image: UIImage) -> UIImage? {
        return drawImageInCircle(cropImageToSquare(image))
    }
}

example("Applying Filters") {
    var request = ImageRequest(URL: NSURL(string: "https://farm4.staticflickr.com/3803/14287618563_b21710bd8c_z_d.jpg")!)
    request.processor = ImageFilterDrawInCircle()
    
    Nuke.taskWith(request) {
        let image = $0.image
    }.resume()
}

/*:
### Composing Filters
It's easy to combine multiple filters using `ImageFilterComposition` class. Lets use a `ImageFilterDrawInCircle` from the previous example and combine it with a gaussian blur filter.
*/

import CoreImage

example("Composing Filters") {
    var request = ImageRequest(URL: NSURL(string: "https://farm4.staticflickr.com/3803/14287618563_b21710bd8c_z_d.jpg")!)
    
    // Compose filters
    let filter = ImageProcessorComposition(processors: [ ImageFilterGaussianBlur(), ImageFilterDrawInCircle()])
    request.processor = filter

    Nuke.taskWith(request) {
        let image = $0.image
    }.resume()
}

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true

//: [Next](@next)
