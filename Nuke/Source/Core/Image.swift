// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

#if os(OSX)
    import Cocoa
    public typealias Image = NSImage
#else
    import UIKit
    public typealias Image = UIImage
#endif
