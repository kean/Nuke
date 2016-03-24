// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Compares keys for equivalence.
public protocol ImageRequestKeyOwner: class {
    /// Compares keys for equivalence. This method is called only if two keys have the same owner.
    func isEqual(lhs: ImageRequestKey, to rhs: ImageRequestKey) -> Bool
}

/// Makes it possible to use ImageRequest as a key in dictionaries.
public final class ImageRequestKey: NSObject {
    /// Request that the receiver was initailized with.
    public let request: ImageRequest

    /// Owner of the receiver.
    public weak private(set) var owner: ImageRequestKeyOwner?

    /// Initializes the receiver with a given request and owner.
    public init(_ request: ImageRequest, owner: ImageRequestKeyOwner) {
        self.request = request
        self.owner = owner
    }

    /// Returns hash from the NSURL from image request.
    public override var hash: Int {
        return request.URLRequest.URL?.hashValue ?? 0
    }

    /// Compares two keys for equivalence if the belong to the same owner.
    public override func isEqual(other: AnyObject?) -> Bool {
        guard let other = other as? ImageRequestKey else {
            return false
        }
        guard let owner = owner where owner === other.owner else {
            return false
        }
        return owner.isEqual(self, to: other)
    }
}
