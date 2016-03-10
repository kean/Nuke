// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(iOS) || os(tvOS)
    import UIKit
    
    extension UIImageView: ImageDisplayingView, ImageLoadingView {
        // Underlying image.
        public var nk_image: UIImage? {
            get { return self.image }
            set { self.image = newValue }
        }
    }
#endif

#if os(OSX)
    import Cocoa
    
    extension NSImageView: ImageDisplayingView, ImageLoadingView {
        // Underlying image.
        public var nk_image: NSImage? {
            get { return self.image }
            set { self.image = newValue }
        }
    }
#endif
