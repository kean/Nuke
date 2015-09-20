// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

/** Use to limit number of concurrent image tasks.
*/
public class ImageTaskQueue {
    public var suspended = false {
        didSet {
            if self.suspended != oldValue && !self.suspended {
                self.setNeedsExecuteTasks()
            }
        }
    }
    private var pendingTasks = [ImageTask]()
    private var executingTasks = Set<ImageTask>()
    private var isExecutingTasks = false
    
    public init() {}
    
    public var maxConcurrentTaskCount = Int.max
    
    public func addTask(task: ImageTask) {
        self.pendingTasks.append(task)
        self.executeTasks()
    }
    
    public func cancelAllTasks() {
        self.pendingTasks.removeAll()
        self.executingTasks.forEach{ $0.cancel() }
    }
    
    private func setNeedsExecuteTasks() {
        if !self.isExecutingTasks {
            self.isExecutingTasks = true
            self.executeTasks()
            self.isExecutingTasks = false
        }
    }
    
    private func executeTasks() {
        while self.shouldExecuteNextTask() {
            guard let task = self.dequeueNextTask() else  {
                return
            }
            self.executingTasks.insert(task)
            task.completion { _ in // ???
                self.executingTasks.remove(task)
                self.setNeedsExecuteTasks()
            }
            task.resume()
        }
    }
    
    private func shouldExecuteNextTask() -> Bool {
        return !self.suspended && self.executingTasks.count < self.maxConcurrentTaskCount
    }
    
    private func dequeueNextTask() -> ImageTask? {
        guard let task = self.pendingTasks.first else { // where is popFirst()?
            return nil
        }
        self.pendingTasks.removeAtIndex(0)
        return task
    }
}
