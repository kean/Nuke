import Nuke
import UIKit
import XCPlayground

/*:
### Using Image Task
`ImageTask` is your primary interface to control image load. After you create a task, you start it by calling its `resume` method. The `ImageManager` that created the task holds a strong reference to it until the task is either completed or cancelled.
*/
example("Using Image Task") {
    let task = Nuke.taskWithURL(NSURL(string: "https://farm6.staticflickr.com/5311/14244377986_a86338d053_z_d.jpg")!)
    print(task.state) // Task is created in Suspened state
    
    task.progress = { completed, total in
        print("progress \(completed) / \(total)")
    }
    
    task.completion {
        let image = $0.image
    }
    task.completion { // Add multiple completions, even for completed task
        let image = $0.image
    }
    
    task.resume()
    
    print(task.state) // Task state changes synchronously on the callers thread
}
/*:
### Cancelling and Suspending Image Task
`ImageTask` can be suspended and cancelled. 

Make sure that you read `NSURLSession` documentation before suspending image tasks. Suspended task might still complete at any time. A download task can continue transferring data at a later time. All other tasks must start over when resumed (actually there is a certain timeout).
*/
example("Cancelling and Suspending Image Task") {
    let task = Nuke.taskWithURL(NSURL(string: "https://farm6.staticflickr.com/5311/14244377986_a86338d053_z_d.jpg")!)
    print(task.state) // Task is created in Suspened state

    task.resume()
    print(task.state)
    
    task.suspend()
    print(task.state)
    
    task.resume()
    print(task.state)
    
    task.cancel()
    print(task.state)
}

XCPSetExecutionShouldContinueIndefinitely()

//: [Next](@next)
