// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
#if os(macOS)
    import Cocoa
#else
    import UIKit
#endif

/// Provides in-memory storage for images.
///
/// The implementation is expected to be thread safe.
public protocol Caching {
    /// Returns an image for the key.
    func image(for key: AnyHashable) -> Image?

    /// Stores the image for the key.
    func setImage(_ image: Image, for key: AnyHashable)
}

public extension Caching {
    /// Returns an image for the request.
    public func image(for request: Request) -> Image? {
        return image(for: Request.cacheKey(for: request))
    }

    /// Stores the image for the request.
    public func setImage(_ image: Image, for request: Request) {
        setImage(image, for: Request.cacheKey(for: request))
    }
}

/// Auto purging memory cache that uses `NSCache` as its internal storage.
public class Cache: Caching {
    deinit {
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.removeObserver(self)
        #endif
    }
    
    // MARK: Configuring Cache
    
    /// The internal memory cache.
    public let cache: NSCache<AnyObject, AnyObject>

    /// Initializes the receiver with a given memory cache.
    public init(cache: NSCache<AnyObject, AnyObject> = Cache.makeDefaultCache()) {
        self.cache = cache
        #if os(iOS) || os(tvOS)
            NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMemoryWarning(_:)), name: .UIApplicationDidReceiveMemoryWarning, object: nil)
        #endif
    }
    
    /// Initializes cache with the recommended cache total limit.
    private static func makeDefaultCache() -> NSCache<AnyObject, AnyObject> {
        let cache = NSCache<AnyObject, AnyObject>()
        cache.totalCostLimit = {
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let ratio = physicalMemory <= (1024 * 1024 * 512 /* 512 Mb */) ? 0.1 : 0.2
            let limit = physicalMemory / UInt64(1 / ratio)
            return limit > UInt64(Int.max) ? Int.max : Int(limit)
        }()
        return cache
    }
    
    // MARK: Managing Cached Images

    /// Stores the image for the key.
    public func image(for key: AnyHashable) -> Image? {
        return cache.object(forKey: AnyHashableObject(key)) as? Image
    }

    /// Stores the image for the key.
    public func setImage(_ image: Image, for key: AnyHashable) {
        cache.setObject(image, forKey: AnyHashableObject(key), cost: cost(image))
    }

    /// Removes an image for the key.
    public func removeImage(for key: AnyHashable) {
        cache.removeObject(forKey: AnyHashableObject(key))
    }

    /// Removes an image for the request.
    public func removeImage(for request: Request) {
        removeImage(for: Request.cacheKey(for: request))
    }

    /// Returns cost for the given image by approximating its bitmap size in bytes in memory.
    public var cost: (Image) -> Int = {
        #if os(macOS)
            return 1
        #else
            guard let cgImage = $0.cgImage else { return 1 }
            return cgImage.bytesPerRow * cgImage.height
        #endif
    }
    
    dynamic private func didReceiveMemoryWarning(_ notification: Notification) {
        cache.removeAllObjects()
    }
}

/// Allows to use Swift Hashable objects with NSCache
private final class AnyHashableObject: NSObject {
    let val: AnyHashable

    init<T: Hashable>(_ val: T) {
        self.val = AnyHashable(val)
    }

    override var hash: Int {
        return val.hashValue
    }

    override func isEqual(_ other: Any?) -> Bool {
        return val == (other as? AnyHashableObject)?.val
    }
}

