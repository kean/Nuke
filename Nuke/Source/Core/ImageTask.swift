// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public enum ImageTaskState {
    case Suspended, Running, Cancelled, Completed
}

public typealias ImageTaskCompletion = (ImageResponse) -> Void
public typealias ImageTaskProgress = (completedUnitCount: Int64, totalUnitCount: Int64) -> Void

/** Abstract class for image tasks. Tasks are always part of the image manager, you create a task by calling one of the methods on ImageManager.
*/
public class ImageTask: Hashable {
    public let request: ImageRequest
    public internal(set) var state: ImageTaskState = .Suspended
    public internal(set) var response: ImageResponse?
    public internal(set) var completedUnitCount: Int64 = 0
    public internal(set) var totalUnitCount: Int64 = 0
    public var hashValue: Int { return self.identifier }
    
    /** Uniquely identifies the task within an image manager.
    */
    public let identifier: Int
    
    /** A progress closure that gets periodically during the lifecycle of the task.
    */
    public var progress: ImageTaskProgress?
    
    public init(request: ImageRequest, identifier: Int) {
        self.request = request
        self.identifier = identifier
    }
    
    /** Adds a closure to be called on the main thread when task is either completed or cancelled.
    
    The closure is called synchronously when the requested image can be retrieved from the memory cache and the request was made from the main thread.
    
    The closure is called even if it is added to the already completed or cancelled task.
    */
    public func completion(completion: ImageTaskCompletion) -> Self { fatalError("Abstract method") }
    
    public func resume() -> Self { fatalError("Abstract method") }
    
    /** Advices the task to suspend loading. If the task is suspended if might still complete at any time.
    
    A download task can continue transferring data at a later time. All other tasks must start over when resumed. For more info on suspending NSURLSessionTask see NSURLSession documentation.
    */
    public func suspend() -> Self { fatalError("Abstract method") }
    
    /** Cancels the task if it hasn't completed yet. Calls a completion closure with an error value of { ImageManagerErrorDomain, ImageManagerErrorCancelled }.
    */
    public func cancel() -> Self { fatalError("Abstract method") }
}

public extension ImageTask {
    public var fractionCompleted: Double {
        guard self.totalUnitCount != 0 else {
            return 0.0
        }
        return Double(self.completedUnitCount) / Double(self.totalUnitCount)
    }
}

public func ==(lhs: ImageTask, rhs: ImageTask) -> Bool {
    return lhs === rhs
}
