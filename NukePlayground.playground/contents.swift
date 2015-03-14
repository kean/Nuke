// Playground - noun: a place where people can play

import UIKit
import XCPlayground
import Nuke

var str = "Hello, playground"

let manager = ImageManager()

let request = ImageRequest(URL: NSURL(string: "https://raw.githubusercontent.com/kean/DFImageManager/master/DFImageManager/Tests/Resources/Image.jpg")!)

let task = manager.imageTaskWithRequest(request, completionHandler: { (response) -> Void in
    //do nothing
})
task.resume()

XCPSetExecutionShouldContinueIndefinitely()
