import Nuke
import UIKit
import XCPlayground
//: ## Nuke



//: Create and customize `ImageRequest`
var request = ImageRequest(URL: NSURL(string: "http://farm8.staticflickr.com/7315/16455839655_7d6deb1ebf_z_d.jpg")!)

// Target size in pixels
request.targetSize = CGSize(width: 400.0, height: 400.0)
request.contentMode = .AspectFit

request.progressHandler = {
    let progress = $0
}

//: Use image manager to create `ImageTask` object and resume it
let task = ImageManager.sharedManager().imageTaskWithRequest(request) { (response) -> Void in
    let error = response.error
    let image = response.image
}
task.resume()

//: Initialize instance of `ImageManager` class with `ImageManagerConfiguration`. Configuration includes URL session manager (`URLSessionManager` class), memory cache (`ImageMemoryCaching` protocol) and image processor (`ImageProcessing` protocol).

let configuration = ImageManagerConfiguration(sessionManager: URLSessionManager(), cache: ImageMemoryCache(), processor: ImageProcessor())
var manager = ImageManager(configuration: configuration)

XCPSetExecutionShouldContinueIndefinitely()
