// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import UIKit

/// Preheating controller for `UITableView`.
public class ImagePreheatingControllerForTableView: ImagePreheatingController {
    /// The table view that the receiver was initialized with.
    public var tableView: UITableView {
        return scrollView as! UITableView
    }

    /// The proportion of the collection view size (either width or height depending on the scroll axis) used as a preheat window.
    public var preheatRectRatio: CGFloat = 1.0

    /// Determines how far the user needs to refresh preheat window.
    public var preheatRectUpdateRatio: CGFloat = 0.33

    private var previousContentOffset = CGPointZero

    /// Initializes the receiver with a given table view.
    public init(tableView: UITableView) {
        super.init(scrollView: tableView)
    }

    /// Default value is false. See superclass for more info.
    public override var enabled: Bool {
        didSet {
            if enabled {
                updatePreheatRect()
            } else {
                previousContentOffset = CGPointZero
                updatePreheatIndexPaths([])
            }
        }
    }

    public override func scrollViewDidScroll() {
        if enabled {
            updatePreheatRect()
        }
    }

    private func updatePreheatRect() {
        let updateMargin = CGRectGetHeight(tableView.bounds) * preheatRectUpdateRatio
        let contentOffset = tableView.contentOffset
        guard distanceBetweenPoints(contentOffset, previousContentOffset) > updateMargin || previousContentOffset == CGPointZero else {
            return
        }
        let scrollDirection: ScrollDirection = (contentOffset.y >= previousContentOffset.y || previousContentOffset == CGPointZero) ? .Forward : .Backward

        previousContentOffset = contentOffset
        let preheatRect = preheatRectInScrollDirection(scrollDirection)
        let preheatIndexPaths = Set(tableView.indexPathsForRowsInRect(preheatRect) ?? []).subtract(tableView.indexPathsForVisibleRows ?? [])
        updatePreheatIndexPaths(sortIndexPaths(preheatIndexPaths, inScrollDirection: scrollDirection))
    }

    private func preheatRectInScrollDirection(direction: ScrollDirection) -> CGRect {
        let viewport = CGRect(origin: tableView.contentOffset, size: tableView.bounds.size)
        let height = CGRectGetHeight(viewport) * preheatRectRatio
        let y = (direction == .Forward) ? CGRectGetMaxY(viewport) : CGRectGetMinY(viewport) - height
        return CGRectIntegral(CGRect(x: 0, y: y, width: CGRectGetWidth(viewport), height: height))
    }
}
