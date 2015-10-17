// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit

extension UIImageView: ImageDisplayingView, ImageLoadingView {
    public var nk_displayedImage: UIImage? {
        get { return self.image }
        set { self.image = newValue }
    }
}
