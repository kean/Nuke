// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

#if os(watchOS)
    import WatchKit
#endif

/// Decodes data into images.
public protocol DataDecoding {
    /// Decodes data into an image object.
    func decode(data: Data, response: URLResponse) -> Image?
}

private let queue = DispatchQueue(label: "\(domain).DataDecoder")

/// Decodes data into an image object. Image scale is set to the scale of the main screen.
public struct DataDecoder: DataDecoding {
    /// Initializes the receiver.
    public init() {}

    /// Decodes data into an image object using native methods.
    public func decode(data: Data, response: URLResponse) -> Image? {
        // Image initializers are not thread safe:
        // - https://github.com/AFNetworking/AFNetworking/issues/2572
        // - https://github.com/Alamofire/AlamofireImage/issues/75
        return queue.sync {
            #if os(OSX)
                return NSImage(data: data)
            #else
                #if os(iOS) || os(tvOS)
                    let scale = UIScreen.main().scale
                #else
                    let scale = WKInterfaceDevice.current().screenScale
                #endif
                return UIImage(data: data, scale: scale)
            #endif
        }
    }
}

public struct DataDecoderFailed: ErrorProtocol {}

public extension DataDecoding {
    public func decode(data: Data, response: URLResponse, scheduler: Scheduler, token: CancellationToken? = nil) -> Promise<Image> {
        return Promise() { fulfill, reject in
            scheduler.execute(token: token) {
                if let image = self.decode(data: data, response: response) {
                    fulfill(value: image)
                } else {
                    reject(error: DataDecoderFailed())
                }
            }
        }
    }
}
