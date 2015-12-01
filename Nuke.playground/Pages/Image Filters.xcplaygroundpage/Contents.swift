import Nuke
import UIKit
import XCPlayground

/*: 
### Applying Filters
Applying image filters is as easy as setting `processor` property on `ImageRequest`. Nuke does all the heavy lifting including storing processed images into memory cache. Creating image filters is also dead simple thanks to `ImageProcessing` protocol and its extensions.
*/
// Create a simple image filter that would draw an image in a circle
class ImageFilterDrawInCircle: ImageProcessing {
    func processImage(image: UIImage) -> UIImage? {
        return drawImageInCircle(cropImageToSquare(image))
    }
}

example("Applying Filters") {
    var request = ImageRequest(URL: NSURL(string: "https://farm4.staticflickr.com/3803/14287618563_b21710bd8c_z_d.jpg")!)
    request.processor = ImageFilterDrawInCircle()
    
    Nuke.taskWithRequest(request) {
        let image = $0.image
    }.resume()
}

/*:
### Composing Filters
It's easy to combine multiple filters using `ImageFilterComposition` class. Lets use a DrawInCircleImageFilter from the previous example and combine it with a new.
*/
import CoreImage

example("Composing Filters") {
    var request = ImageRequest(URL: NSURL(string: "https://farm4.staticflickr.com/3803/14287618563_b21710bd8c_z_d.jpg")!)
    
    // Compose filters
    let filter = ImageProcessorComposition(processors: [ ImageFilterGaussianBlur(), ImageFilterDrawInCircle()])
    request.processor = filter

    Nuke.taskWithRequest(request) {
        let image = $0.image
    }.resume()
}

XCPSetExecutionShouldContinueIndefinitely()

//: [Next](@next)
