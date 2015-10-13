// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public enum ImageTaskState {
    case Suspended, Running, Cancelled, Completed
}

public typealias ImageTaskCompletion = (ImageResponse) -> Void
public typealias ImageTaskProgress = (completedUnitCount: Int64, totalUnitCount: Int64) -> Void

/** Abstract class
*/
public class ImageTask: Hashable {
    public let request: ImageRequest
    public let identifier: Int
    public internal(set) var state: ImageTaskState = .Suspended
    public internal(set) var response: ImageResponse?
    public internal(set) var completedUnitCount: Int64 = 0
    public internal(set) var totalUnitCount: Int64 = 0
    public var progress: ImageTaskProgress?
    
    public init(request: ImageRequest, identifier: Int) {
        self.request = request
        self.identifier = identifier
    }
    
    public var hashValue: Int {
        return self.identifier
    }
    
    /** Adds completion block to the task. Completion block is called even if it is added to the alredy completed task.
    
    Completion block to be called on the main thread when task is either completed or cancelled. Completion block is called synchronously when the requested image can be retrieved from the memory cache and the request was made from the main thread.
    */
    public func completion(completion: ImageTaskCompletion) -> Self { fatalError("Abstract method") }

    public func resume() -> Self { fatalError("Abstract method") }
    
    /** Advices image task to suspend loading. Suspended task might still complete at any time. A download task can continue transferring data at a later time. All other tasks must start over when resumed. For more info on suspending NSURLSessionTask see NSURLSession documentation.
    */
    public func suspend() -> Self { fatalError("Abstract method") }
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
