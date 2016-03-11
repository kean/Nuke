import Nuke
import UIKit
import XCPlayground

/*:
### Using Image Task
`ImageTask` is your primary interface to control image load. After you create a task, you start it by calling its `resume` method. The `ImageManager` that created the task holds a strong reference to it until the task is either completed or cancelled.
*/
example("Using Image Task") {
    let task = Nuke.taskWith(NSURL(string: "https://farm6.staticflickr.com/5311/14244377986_a86338d053_z_d.jpg")!)
    print(task.state) // Task is created in Suspened state
    
    task.progressHandler = { progress in
        print("progress \(progress.completed) / \(progress.total)")
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

example("Cancelling Image Task") {
    let task = Nuke.taskWith(NSURL(string: "https://farm6.staticflickr.com/5311/14244377986_a86338d053_z_d.jpg")!)
    print(task.state) // Task is created in Suspened state

    task.resume()
    print(task.state)

    
    task.cancel()
    print(task.state)
}

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true

//: [Next](@next)
