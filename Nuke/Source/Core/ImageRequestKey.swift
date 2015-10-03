//
//  ImageRequestKey.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 03/10/15.
//  Copyright © 2015 Alexander Grebenyuk. All rights reserved.
//

import Foundation

internal protocol ImageRequestKeyOwner: class {
    func isImageRequestKey(key: ImageRequestKey, equalToKey: ImageRequestKey) -> Bool
}

internal enum ImageRequestKeyType {
    case Load, Cache
}

/** Makes it possible to use ImageRequest as a key in dictionaries, sets, etc
*/
internal class ImageRequestKey: NSObject {
    internal let request: ImageRequest
    internal let type: ImageRequestKeyType
    internal weak var owner: ImageRequestKeyOwner?
    
    internal init(_ request: ImageRequest, type: ImageRequestKeyType, owner: ImageRequestKeyOwner) {
        self.request = request
        self.type = type
        self.owner = owner
    }
    
    internal override var hash: Int {
        return self.request.URL.hashValue
    }
    
    internal override func isEqual(other: AnyObject?) -> Bool {
        guard let other = other as? ImageRequestKey else {
            return false
        }
        guard let owner = self.owner where self.owner === other.owner && self.type == other.type else {
            return false
        }
        return owner.isImageRequestKey(self, equalToKey: other)
    }
}
