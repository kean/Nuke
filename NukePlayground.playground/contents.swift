import Nuke
import UIKit
import XCPlayground
//: ## Nuke

//: Use shared image manager to create `ImageTask` with `NSURL`. Resume created task to start the download. You can cancel the task at any time by calling its `cancel()` method.
let URL = NSURL(string: "http://farm8.staticflickr.com/7315/16455839655_7d6deb1ebf_z_d.jpg")!
let task = ImageManager.sharedManager().imageTaskWithURL(URL) {
    (image: UIImage?, error: NSError?) -> Void in
    let image = image
}
task.resume()

//: Create and customize `ImageRequest` and use it to create `ImageTask`. You can provide a target size and content mode that specify how to resize donwloaded image. You can also add a progress handler.
var request = ImageRequest(URL: NSURL(string: "http://farm4.staticflickr.com/3892/14940786229_5b2b48e96c_z_d.jpg")!)
request.targetSize = CGSize(width: 10.0, height: 400.0) // Set target size in pixels
request.contentMode = .AspectFit
request.progressHandler = {
    let progress = $0 // Observe download progress
}

let task2 = ImageManager.sharedManager().imageTaskWithRequest(request) { (image: UIImage?, error: NSError?) -> Void in
    let image = image
    let error = error
}
task2.resume()

//: Initialize instance of `ImageManager` class with `ImageManagerConfiguration`. Configuration includes URL session manager (`URLSessionManager` class), memory cache (`ImageMemoryCaching` protocol) and image processor (`ImageProcessing` protocol).

// Provide your own NSURLSessionConfiguration
let sessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration()
let sessionManager: URLSessionManager = URLSessionManager(sessionConfiguration: sessionConfiguration)

let cache: ImageMemoryCaching = ImageMemoryCache()
let processor: ImageProcessing = ImageProcessor()

let manager = ImageManager(configuration: ImageManagerConfiguration(sessionManager: sessionManager, cache: cache, processor: nil))

// Change shared manager
ImageManager.setSharedManager(manager)

XCPSetExecutionShouldContinueIndefinitely()
