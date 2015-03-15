// Playground - noun: a place where people can play

import Nuke
import UIKit
import XCPlayground

var str = "Hello, playground"

let manager = ImageManager(sessionManager: URLSessionManager())

let request = ImageRequest(URL: NSURL(string: "https://raw.githubusercontent.com/kean/DFImageManager/master/DFImageManager/Tests/Resources/Image.jpg")!)

println("we are here")

let task = manager.imageTaskWithRequest(request) { (response) -> Void in
    let image = response.image
}
task.resume()

XCPSetExecutionShouldContinueIndefinitely()
