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
public protocol Caching: class {
    /// Accesses the image associated with the given key.
    subscript(key: AnyHashable) -> Image? { get set }
}

public extension Caching {
    /// Accesses the image associated with the given request.
    subscript(request: Request) -> Image? {
        get { return self[Request.cacheKey(for: request)] }
        set { self[Request.cacheKey(for: request)] = newValue }
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

    /// Accesses the image associated with the given key.
    public subscript(key: AnyHashable) -> Image? {
        get {
            return cache.object(forKey: Key(key)) as? Image
        }
        set {
            if let image = newValue {
                cache.setObject(image, forKey: Key(key), cost: cost(image))
            } else {
                cache.removeObject(forKey: Key(key))
            }
        }
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
    
    /// Wraps `Hashable` types in NSObject (required by NSCache)
    private final class Key: NSObject {
        let val: AnyHashable
        
        init(_ val: AnyHashable) { self.val = val }
        
        override var hash: Int { return val.hashValue }
        
        override func isEqual(_ other: Any?) -> Bool {
            return val == (other as? Key)?.val
        }
    }
}
