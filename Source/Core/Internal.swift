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

func dispathOnMainThread(closure: (Void) -> Void) {
    NSThread.isMainThread() ? closure() : dispatch_async(dispatch_get_main_queue(), closure)
}

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

extension NSOperationQueue {
    convenience init(maxConcurrentOperationCount: Int) {
        self.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
}
