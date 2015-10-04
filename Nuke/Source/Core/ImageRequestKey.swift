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

/** Makes it possible to use ImageRequest as a key in dictionaries, sets, etc
*/
internal class ImageRequestKey: NSObject {
    internal let request: ImageRequest
    internal weak var owner: ImageRequestKeyOwner?
    
    internal init(_ request: ImageRequest, owner: ImageRequestKeyOwner) {
        self.request = request
        self.owner = owner
    }
    
    internal override var hash: Int {
        return self.request.URL.hashValue
    }
    
    internal override func isEqual(other: AnyObject?) -> Bool {
        guard let other = other as? ImageRequestKey else {
            return false
        }
        guard let owner = self.owner where self.owner === other.owner else {
            return false
        }
        return owner.isImageRequestKey(self, equalToKey: other)
    }
}
