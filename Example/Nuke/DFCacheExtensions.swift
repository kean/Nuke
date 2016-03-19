//
//  DFCacheExtensions.swift
//  Nuke Demo
//
//  Created by Alexander Grebenyuk on 18/03/16.
//  Copyright © 2016 CocoaPods. All rights reserved.
//

import Foundation
import DFCache
import Nuke

extension DFDiskCache: ImageDiskCaching {
    public func setData(data: NSData, response: NSURLResponse, forTask task: ImageTask) {
        if let key = toKey(task) {
            setData(data, forKey: key)
        }
    }
    
    public func dataFor(task: ImageTask) -> NSData? {
        if let key = toKey(task) {
            return dataForKey(key)
        }
        return nil
    }
    
    public func removeAllCachedImages() {
        removeAllData()
    }

    private func toKey(task: ImageTask) -> String? {
        return task.request.URLRequest.URL?.absoluteString
    }
}
