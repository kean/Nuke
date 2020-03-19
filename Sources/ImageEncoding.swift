// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

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
    func encode(image: PlatformImage) -> Data?
}

// MARK: - ImageEncoder

public struct ImageEncoder: ImageEncoding {
    private let compressionQuality: CGFloat

    init(compressionQuality: CGFloat = 0.8) {
        self.compressionQuality = compressionQuality
    }

    public func encode(image: PlatformImage) -> Data? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        if cgImage.isOpaque {
            return ImageEncoder.jpegData(from: image, compressionQuality: compressionQuality)
        } else {
            return ImageEncoder.pngData(from: image)
        }
    }
}

/// Image encoding context used when selecting which encoder to use.
public struct ImageEncodingContext {
    public let request: ImageRequest
    public let image: PlatformImage
    public let urlResponse: URLResponse?
}

#if !os(macOS)
extension ImageEncoder {
    static func pngData(from image: UIImage) -> Data? {
        return image.pngData()
    }

    static func jpegData(from image: UIImage, compressionQuality: CGFloat) -> Data? {
        return image.jpegData(compressionQuality: compressionQuality)
    }
}
#else
extension ImageEncoder {
    static func pngData(from image: NSImage) -> Data? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    static func jpegData(from image: NSImage, compressionQuality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}
#endif
