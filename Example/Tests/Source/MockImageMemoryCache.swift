//
//  MockImageMemoryCache.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 04/10/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import Nuke

class MockImageMemoryCache: ImageMemoryCaching {
    var enabled = true
    var responses = [ImageRequestKey: ImageCachedResponse]()
    init() {}
    
    func cachedResponseForKey(key: ImageRequestKey) -> ImageCachedResponse? {
        return self.enabled ? self.responses[key] : nil
    }
    
    func storeResponse(response: ImageCachedResponse, forKey key: ImageRequestKey) {
        if self.enabled {
            self.responses[key] = response
        }
    }
    
    func removeAllCachedImages() {
        self.responses.removeAll()
    }
}
