//
//  ImageRequestKey.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 03/10/15.
//  Copyright © 2015 Alexander Grebenyuk. All rights reserved.
//

import Foundation

public protocol ImageRequestKeyOwner: class {
    func isImageRequestKey(key: ImageRequestKey, equalToKey: ImageRequestKey) -> Bool
}

/** Makes it possible to use ImageRequest as a key in dictionaries.
*/
public class ImageRequestKey: NSObject {
    public let request: ImageRequest
    public weak private(set) var owner: ImageRequestKeyOwner?
    
    public init(_ request: ImageRequest, owner: ImageRequestKeyOwner) {
        self.request = request
        self.owner = owner
    }
    
    public override var hash: Int {
        return self.request.URLRequest.URL?.hashValue ?? 0
    }
    
    public override func isEqual(other: AnyObject?) -> Bool {
        guard let other = other as? ImageRequestKey else {
            return false
        }
        guard let owner = self.owner where self.owner === other.owner else {
            return false
        }
        return owner.isImageRequestKey(self, equalToKey: other)
    }
}
