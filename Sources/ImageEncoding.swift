// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

#if !os(macOS)
import UIKit
#else
import Cocoa
#endif

#if os(watchOS)
import WatchKit
#endif

// MARK: - ImageEncoding

public protocol ImageEncoding {
    func encode(image: Image) -> Data?
}

#if !os(macOS)
// MARK: - ImageEncoder

public struct ImageEncoder: ImageEncoding {
    private let compressionQuality: CGFloat

    init(compressionQuality: CGFloat = 0.8) {
        self.compressionQuality =  compressionQuality
    }

    public func encode(image: Image) -> Data? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        if ImageProcessor.isTransparent(cgImage) {
            return image.pngData()
        } else {
            return image.jpegData(compressionQuality: compressionQuality)
        }
    }
}
#endif
