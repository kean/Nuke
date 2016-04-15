// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
    /// Alias for NSImage
    public typealias Image = NSImage
#else
    import UIKit
    /// Alias for UIImage
    public typealias Image = UIImage
#endif


// MARK: Error Handling

func errorWithCode(code: ImageManagerErrorCode) -> NSError {
    func reason() -> String {
        switch code {
        case .Unknown: return "The image manager encountered an error that it cannot interpret."
        case .Cancelled: return "The image task was cancelled."
        case .DecodingFailed: return "The image manager failed to decode image data."
        case .ProcessingFailed: return "The image manager failed to process image data."
        }
    }
    return NSError(domain: ImageManagerErrorDomain, code: code.rawValue, userInfo: [NSLocalizedFailureReasonErrorKey: reason()])
}


// MARK: GCD

func dispathOnMainThread(closure: (Void) -> Void) {
    NSThread.isMainThread() ? closure() : dispatch_async(dispatch_get_main_queue(), closure)
}

extension dispatch_queue_t {
    func async(block: (Void -> Void)) { dispatch_async(self, block) }
}


// MARK: NSOperationQueue Extensions

extension NSOperationQueue {
    convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
    
    func addBlock(block: (Void -> Void)) -> NSOperation {
        let operation = NSBlockOperation(block: block)
        self.addOperation(operation)
        return operation
    }
}


// MARK: TaskQueue

public let SessionTaskDidResumeNotification = "com.github.kean.nuke.sessionTaskDidResume"
public let SessionTaskDidCancelNotification = "com.github.kean.nuke.sessionTaskDidCancel"
public let SessionTaskDidCompleteNotification = "com.github.kean.nuke.sessionTaskDidComplete"

/// Limits number of concurrent tasks, prevents trashing of NSURLSession
final class TaskQueue {
    var maxExecutingTaskCount = 8
    var congestionControlEnabled = true
    
    private let queue: dispatch_queue_t
    private var pendingTasks = NSMutableOrderedSet()
    private var executingTasks = Set<NSURLSessionTask>()
    private var executing = false
    
    init(queue: dispatch_queue_t) {
        self.queue = queue
    }
    
    func resume(task: NSURLSessionTask) {
        if !pendingTasks.containsObject(task) && !executingTasks.contains(task) {
            pendingTasks.addObject(task)
            setNeedsExecute()
        }
    }
    
    func cancel(task: NSURLSessionTask) {
        if pendingTasks.containsObject(task) {
            pendingTasks.removeObject(task)
        } else if executingTasks.contains(task) {
            executingTasks.remove(task)
            task.cancel()
            NSNotificationCenter.defaultCenter().postNotificationName(SessionTaskDidCancelNotification, object: task)
            setNeedsExecute()
        }
    }
    
    func finish(task: NSURLSessionTask) {
        if pendingTasks.containsObject(task) {
            pendingTasks.removeObject(task)
        } else if executingTasks.contains(task) {
            executingTasks.remove(task)
            NSNotificationCenter.defaultCenter().postNotificationName(SessionTaskDidCompleteNotification, object: task)
            setNeedsExecute()
        }
    }
    
    func setNeedsExecute() {
        if !executing {
            executing = true
            if congestionControlEnabled {
                // Executing tasks too frequently might trash NSURLSession to the point it would crash or stop executing tasks
                let delay = min(30.0, 8.0 + Double(executingTasks.count))
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_MSEC))), queue) {
                    self.execute()
                }
            } else {
                execute()
            }
        }
    }
    
    func execute() {
        executing = false
        if let task = pendingTasks.firstObject as? NSURLSessionTask where executingTasks.count < maxExecutingTaskCount {
            pendingTasks.removeObjectAtIndex(0)
            executingTasks.insert(task)
            task.resume()
            NSNotificationCenter.defaultCenter().postNotificationName(SessionTaskDidResumeNotification, object: task)
            setNeedsExecute()
        }
    }
}
