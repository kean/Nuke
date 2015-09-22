import Nuke
import UIKit
import XCPlayground

//: Create and resume `ImageTask` with `NSURL`
let URL = NSURL(string: "https://farm8.staticflickr.com/7315/16455839655_7d6deb1ebf_z_d.jpg")!
let task = Nuke.taskWithURL(URL) {
    let image = $0.image
}.resume()

//: Create and resume `ImageTask` with `ImageRequest`
var request = ImageRequest(URL: NSURL(string: "http://farm4.staticflickr.com/3892/14940786229_5b2b48e96c_z_d.jpg")!)
request.targetSize = CGSize(width: 100.0, height: 100.0) // Set target size in pixels
request.contentMode = .AspectFill

Nuke.taskWithRequest(request) { response in
    switch response { // Response is an enum with associated values
    case let .Success(image, _):
        let image = image
    case let .Failure(error):
        let error = error
    }
}.resume()

//: Create and apply image filter

class DrawInCircleImageFilter: ImageProcessing {
    func processImage(image: UIImage) -> UIImage? {
        return drawImageInCircle(cropImageToSquare(image))
    }
}

var request2 = ImageRequest(URL: NSURL(string: "https://farm4.staticflickr.com/3803/14287618563_b21710bd8c_z_d.jpg")!)
request2.processor = DrawInCircleImageFilter()

Nuke.taskWithRequest(request2) {
    let image = $0.image
}.resume()

//: Create `ImageManager` with custom `ImageManagerConfiguration` and set it as shared manager

let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
let dataLoader = ImageDataLoader(sessionConfiguration: sessionConfiguration)
let cache = ImageMemoryCache()
let decoder = ImageDecoder()

ImageManager.shared = ImageManager(configuration: ImageManagerConfiguration(dataLoader: dataLoader, cache: cache, decoder: decoder))

XCPSetExecutionShouldContinueIndefinitely()

