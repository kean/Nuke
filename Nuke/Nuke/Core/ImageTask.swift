// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

public enum ImageTaskState {
    case Suspended
    case Running
    case Cancelled
    case Completed
}

/** Abstract class
*/
public class ImageTask: Hashable {
    public let request: ImageRequest
    public var completion: ImageTaskCompletion?
    public internal(set) var state: ImageTaskState = .Suspended
    public internal(set) var response: ImageResponse?
    public let progress: NSProgress
    
    internal init(request: ImageRequest, completion: ImageTaskCompletion?) {
        self.request = request
        self.completion = completion
        self.progress = NSProgress(totalUnitCount: -1)
        self.progress.cancellationHandler = {
            [weak self] in self?.cancel()
        }
    }
    
    public var hashValue: Int {
        return self.request.URL.hashValue
    }
    
    public func resume() -> Self { return self }
    public func cancel() -> Self { return self }
}

public func ==(lhs: ImageTask, rhs: ImageTask) -> Bool {
    return lhs === rhs
}
