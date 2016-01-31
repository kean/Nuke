// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation

/** Compares keys for equivalence.
 */
public protocol ImageRequestKeyOwner: class {
    /** Compares keys for equivalence. This method is called only if two keys have the same owner.
     */
    func isEqual(lhs: ImageRequestKey, to rhs: ImageRequestKey) -> Bool
}

/** Makes it possible to use ImageRequest as a key in dictionaries.
 */
public class ImageRequestKey: NSObject {
    /** Request that the receiver was initailized with.
     */
    public let request: ImageRequest

    /** Owner of the receiver.
     */
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
        return owner.isEqual(self, to: other)
    }
}
