// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

#if os(macOS)
import Cocoa
#else
import UIKit
#endif

#if os(watchOS)
import WatchKit
#endif

// MARK: - ImageDecoding

/// Decodes image data.
public protocol ImageDecoding {
    /// Produces an image from the image data. A decoder is a one-shot object
    /// created for a single image decoding session. If image pipeline has
    /// progressive decoding enabled, the `decode(data:isFinal:)` method gets
    /// called each time the data buffer has new data available. The decoder may
    /// decide whether or not to produce a new image based on the previous scans.
    func decode(data: Data, isFinal: Bool) -> Image?
}

// An image decoder that uses native APIs. Supports progressive decoding.
// The decoder is stateful.
public final class ImageDecoder: ImageDecoding {
    // `nil` if decoder hasn't detected whether progressive decoding is enabled.
    private(set) internal var isProgressive: Bool?
    // Number of scans that the decoder has found so far. The last scan might be
    // incomplete at this point.
    private(set) internal var numberOfScans = 0
    private var scannedIndex: Int = 0 // Index at which previous scan was finished

    public init() { }

    public func decode(data: Data, isFinal: Bool) -> Image? {
        guard !isFinal else { return _decode(data) } // Just decode the data.

        // Determined (if we haven't yet) whether the image supports progressive
        // decoding or not (only proressive JPEG is allowed for now, but you can
        // add support for other formats by implementing your own decoder).
        isProgressive = isProgressive ?? ImageDecoder.isProgressiveJPEG(data: data)
        guard isProgressive == true else { return nil }

        // Check if there is more data to scan.
        guard scannedIndex < data.count else { return nil }

        // Start scaning from the where we left off previous time.
        var index = scannedIndex
        var numberOfScans = self.numberOfScans
        while index < (data.count - 1) {
            scannedIndex = index
            // 0xFF, 0xDA - Start Of Scan
            if data[index] == 0xFF, data[index+1] == 0xDA {
                numberOfScans += 1
            }
            index += 1
        }

        // Found more scans this time
        guard numberOfScans > self.numberOfScans else { return nil }
        self.numberOfScans = numberOfScans

        // `> 1` checks that we've received a first scan (SOS) and then received
        // and also received a second scan (SOS). This way we know that we have
        // at least one full scan available.
        return numberOfScans > 1 ? _decode(data) : nil
    }
}

// Image initializers are documented as fully-thread safe:
//
// > The immutable nature of image objects also means that they are safe
//   to create and use from any thread.
//
// However, there are some versions of iOS which violated this. The
// `UIImage` is supposably fully thread safe again starting with iOS 10.
//
// The `queue.sync` call below prevents the majority of the potential
// crashes that could happen on the previous versions of iOS.
//
// See also https://github.com/AFNetworking/AFNetworking/issues/2572
private let _queue = DispatchQueue(label: "com.github.kean.Nuke.DataDecoder")

internal func _decode(_ data: Data) -> Image? {
    return _queue.sync {
        #if os(macOS)
        return NSImage(data: data)
        #else
        #if os(iOS) || os(tvOS)
        let scale = UIScreen.main.scale
        #else
        let scale = WKInterfaceDevice.current().screenScale
        #endif
        return UIImage(data: data, scale: scale)
        #endif
    }
}

extension ImageDecoder {
    // Detects if the data contains a jpeg image (or at least the magic number
    // match) and then detect if it's progressive (not baseline).
    // A example of first few bytes of progressive jpeg image:
    // FF D8 FF E0 00 10 4A 46 49 46 00 01 01 00 00 48 00 ...
    // Returns `nil` if not enough data has been loaded.
    internal static func isProgressiveJPEG(data: Data) -> Bool? {
        guard data.count >= 3 else { return nil } // Not enough data

        // First make sure that it's a jpeg using JPEG magic numbers.
        // https://en.wikipedia.org/wiki/JPEG
        guard data[0] == 0xFF, data[1] == 0xD8, data[2] == 0xFF else { return false }

        // Find a first start of frame and check if it's a progressive one.
        var index = 3 // start scanning right after magic numbers
        while index < (data.count - 1) {
            // 0xFF, 0xC0 - Start Of Frame (baseline DCT)
            // 0xFF, 0xC2 - Start Of Frame (progressive DCT)
            // https://en.wikipedia.org/wiki/JPEG
            if data[index] == 0xFF {
                if data[index+1] == 0xC2 { return true } // progressive
                if data[index+1] == 0xC0 { return false } // baseline
            }
            index += 1
        }
        return nil // Not enough data
    }
}

// MARK: - ImageDecoderRegistry

/// A register of image codecs (only decoding).
public final class ImageDecoderRegistry {
    /// A shared registry.
    public static let shared = ImageDecoderRegistry()

    private var matches = [(ImageDecodingContext) -> ImageDecoding?]()

    /// Returns a decoder which matches the given context.
    public func decoder(for context: ImageDecodingContext) -> ImageDecoding {
        for match in matches {
            if let decoder = match(context) {
                return decoder
            }
        }
        return ImageDecoder() // Return default decoder if couldn't find a custom one.
    }

    /// Registers a decoder to be used in a given decoding context. The closure
    /// is going to be executed before all other already registered closures.
    public func register(_ match: @escaping (ImageDecodingContext) -> ImageDecoding?) {
        matches.insert(match, at: 0)
    }
}
