// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation
import UIKit

/** Signals the delegate that the preheat window changed.
*/
public protocol ImagePreheatingControllerDelegate: class {
    func preheatingController(controller: ImagePreheatingController, didUpdateWithAddedIndexPaths addedIndexPaths: [NSIndexPath], removedIndexPaths: [NSIndexPath])
}

/** Automates image preheating. Abstract class.
*/
public class ImagePreheatingController: NSObject {
    public weak var delegate: ImagePreheatingControllerDelegate?
    public let scrollView: UIScrollView
    public private(set) var preheatIndexPath = [NSIndexPath]()
    public var enabled = false
    
    deinit {
        self.scrollView.removeObserver(self, forKeyPath: "contentOffset", context: nil)
    }
    
    public init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init()
        self.scrollView.addObserver(self, forKeyPath: "contentOffset", options: [.New], context: nil)
    }
    
    public override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if object === self.scrollView {
            self.scrollViewDidScroll()
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: nil)
        }
    }
    
    // MARK: Subclassing Hooks
        
    public func scrollViewDidScroll() {
        assert(false)
    }
    
    public func updatePreheatIndexPaths(indexPaths: [NSIndexPath]) {
        let addedIndexPaths = indexPaths.filter { return !self.preheatIndexPath.contains($0) }
        let removedIndexPaths = Set(self.preheatIndexPath).subtract(indexPaths)
        self.preheatIndexPath = indexPaths
        self.delegate?.preheatingController(self, didUpdateWithAddedIndexPaths: addedIndexPaths, removedIndexPaths: Array(removedIndexPaths))
    }
}

internal func distanceBetweenPoints(p1: CGPoint, _ p2: CGPoint) -> CGFloat {
    let dx = p2.x - p1.x, dy = p2.y - p1.y
    return sqrt((dx * dx) + (dy * dy))
}
