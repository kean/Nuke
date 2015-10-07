// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

/** Signals the delegate that the preheat window changed significantly.

Added index paths are sorted so that the items closest to the previous preheat window are in the beginning of the array, true for both scrolling directions (forward and backward).
*/
public protocol ImagePreheatingControllerDelegate: class {
    func preheatingController(controller: ImagePreheatingController, didUpdateWithAddedIndexPaths addedIndexPaths: [NSIndexPath], removedIndexPaths: [NSIndexPath])
}

public class ImagePreheatingController: NSObject {
    public weak var delegate: ImagePreheatingControllerDelegate?
    public let scrollView: UIScrollView
    public private(set) var preheatIndexPath = Set<NSIndexPath>()
    
    deinit {
        self.scrollView.removeObserver(self, forKeyPath: "contentOffset", context: nil)
    }
    
    public init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init()
        self.scrollView.addObserver(self, forKeyPath: "contentOffset", options: [.New], context: nil)
    }
    
    public func reset() {
        self.delegate?.preheatingController(self, didUpdateWithAddedIndexPaths: [], removedIndexPaths: Array(self.preheatIndexPath))
        self.preheatIndexPath.removeAll()
    }
    
    public func update() {
        return
    }
    
    // MARK: Subclassing Hooks
    
    public override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if object === self.scrollView {
            self.scrollViewDidScroll()
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: nil)
        }
    }
    
    internal func scrollViewDidScroll() {
        return
    }
    
    internal func updatePreheatIndexPaths(indexPaths: Set<NSIndexPath>, scrollingForward: Bool) {
        let oldIndexPaths = Set(self.preheatIndexPath)
        
        var addedIndexPaths = Set(indexPaths)
        addedIndexPaths = addedIndexPaths.subtract(oldIndexPaths)
        
        var removedIndexPaths = Set(oldIndexPaths)
        removedIndexPaths = removedIndexPaths.subtract(indexPaths)
        
        self.preheatIndexPath = indexPaths
        
        let sortedAddedIndexPath = Array(addedIndexPaths).sort {
            if scrollingForward {
                return $0.section < $1.section || $0.item < $1.item
            } else {
                return $0.section > $1.section || $0.item > $1.item
            }
        }
        
        self.delegate?.preheatingController(self, didUpdateWithAddedIndexPaths: sortedAddedIndexPath, removedIndexPaths: Array(removedIndexPaths))
    }
}
