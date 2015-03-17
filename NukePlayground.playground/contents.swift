import Nuke
import UIKit
import XCPlayground
//: ## Nuke

//: Initialize instance of `ImageManager` class with `ImageManagerConfiguration`. Configuration includes:

let configuration = ImageManagerConfiguration(sessionManager: URLSessionManager(), cache: ImageMemoryCache(), processor: ImageProcessor())
let manager = ImageManager(configuration: configuration)

//: Create and customize `ImageRequest`
var request = ImageRequest(URL: NSURL(string: "http://farm8.staticflickr.com/7315/16455839655_7d6deb1ebf_z_d.jpg")!)

// Target size in pixels
request.targetSize = CGSize(width: 400.0, height: 400.0)
request.contentMode = .AspectFit

//: Use image manager to create `ImageTask` object and resume it
let task = manager.imageTaskWithRequest(request) { (response) -> Void in
    let error = response.error
    let image = response.image
}
task.resume()

XCPSetExecutionShouldContinueIndefinitely()
