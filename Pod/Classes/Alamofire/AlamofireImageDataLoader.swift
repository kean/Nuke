// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit
import Alamofire

public class AlamofireImageDataLoader: ImageDataLoading {
    public let manager: Alamofire.Manager
    
    public init(manager: Alamofire.Manager = Alamofire.Manager.sharedInstance) {
        self.manager = manager
    }
    
    // MARK: ImageDataLoading
    
    public func isRequestLoadEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool {
        return lhs.URL.isEqual(rhs.URL)
    }
    
    public func isRequestCacheEquivalent(lhs: ImageRequest, toRequest rhs: ImageRequest) -> Bool {
        return lhs.URL.isEqual(rhs.URL)
    }
    
    public func imageDataTaskWithURL(url: NSURL, progressHandler: ImageDataLoadingProgressHandler, completionHandler: ImageDataLoadingCompletionHandler) -> NSURLSessionDataTask {
        let task = self.manager.request(.GET, url, parameters: nil).response { (_, response, data, error) -> Void in
            completionHandler(data: data, response: response, error: error)
        }.progress { (_, totalBytesReceived, totalBytesExpected) -> Void in
            progressHandler(completedUnitCount: totalBytesReceived, totalUnitCount: totalBytesExpected)
        }
        return task.task as! NSURLSessionDataTask
    }
    
    public func invalidate() {
        self.manager.session.invalidateAndCancel()
    }
    
    public func removeAllCachedImages() {
        self.manager.session.configuration.URLCache?.removeAllCachedResponses()
    }
}
