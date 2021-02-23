// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import CoreGraphics

public extension ImageProcessors.Resize {
    // Deprecated in 9.2.2
    @available(*, deprecated, message: "Please use an initialzier without `crop` parameter.")
    init(width: CGFloat, unit: ImageProcessingOptions.Unit = .points, crop: Bool, upscale: Bool = false) {
        self.init(size: CGSize(width: width, height: 9999), unit: unit, contentMode: .aspectFit, crop: crop, upscale: upscale)
    }

    @available(*, deprecated, message: "Please use an initialzier without `crop` parameter.")
    init(height: CGFloat, unit: ImageProcessingOptions.Unit = .points, crop: Bool, upscale: Bool = false) {
        self.init(size: CGSize(width: 9999, height: height), unit: unit, contentMode: .aspectFit, crop: crop, upscale: upscale)
    }
}

public extension ImagePipeline.Configuration {
    // Deprecated in 9.0
    @available(*, deprecated, message: "Please use `dataCacheOptions.contents` instead.")
    var isDataCachingForOriginalImageDataEnabled: Bool {
        get {
            dataCacheOptions.storedItems.contains(.originalImageData)
        }
        set {
            if newValue {
                dataCacheOptions.storedItems.insert(.originalImageData)
            } else {
                dataCacheOptions.storedItems.remove(.originalImageData)
            }
        }
    }

    // Deprecated in 9.0
    @available(*, deprecated, message: "Please use `dataCacheOptions.contents` instead. Please note that the new behavior is different from the previous versions. Now, instead of storing only processd image, it encodes and stores all downloaded images.")
    var isDataCachingForProcessedImagesEnabled: Bool {
        get {
            dataCacheOptions.storedItems.contains(.finalImage)
        }
        set {
            if newValue {
                dataCacheOptions.storedItems.insert(.finalImage)
            } else {
                dataCacheOptions.storedItems.remove(.finalImage)
            }
        }
    }

    /// - warning: Soft-deprecated in 9.0. The default image decoder now
    /// automatically attaches image data to the newly added ImageContainer type.
    /// To learn how to implement animated image support using this new type,
    /// see the new Image Formats guide https://github.com/kean/Nuke/blob/9.3.0/Documentation/Guides/image-formats.md"
    static var isAnimatedImageDataEnabled: Bool {
        get { _isAnimatedImageDataEnabled }
        set { _isAnimatedImageDataEnabled = newValue }
    }
}

public extension ImageProcessingContext {
    // Deprecated in 9.0
    @available(*, deprecated, message: "Please use `response.container.userInfo[ImageDecoders.Default.scanNumberKey]` instead.")
    var scanNumber: Int? {
        return response.container.userInfo[ImageDecoders.Default.scanNumberKey] as? Int
    }
}

// Deprecated in 9.0
@available(*, deprecated, message: "Renamed to `ImageProcessors`")
public typealias ImageProcessor = ImageProcessors

public extension ImageProcessors {
    // Deprecated in 9.0
    @available(*, deprecated, message: "Renamed to `ImageProcessingOptions.Unit` to avoid polluting `ImageProcessors` namescape with non-processors.")
    typealias Unit = ImageProcessingOptions.Unit

    #if !os(macOS)
    // Deprecated in 9.0
    @available(*, deprecated, message: "Renamed to `ImageProcessingOptions.Border` to avoid polluting `ImageProcessors` namescape with non-processors.")
    typealias Border = ImageProcessingOptions.Border
    #endif
}

private var _animatedImageDataAK = "Nuke.AnimatedImageData.AssociatedKey"

extension PlatformImage {
    /// - warning: Soft-deprecated in Nuke 9.0.
    public var animatedImageData: Data? {
        get { _animatedImageData }
        set { _animatedImageData = newValue }
    }

    // Deprecated in 9.0
    internal var _animatedImageData: Data? {
        get { objc_getAssociatedObject(self, &_animatedImageDataAK) as? Data }
        set { objc_setAssociatedObject(self, &_animatedImageDataAK, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

public extension DataCaching {
    // Deprecated in 9.2
    @available(*, deprecated, message: "This method exists for backward-compatibility with Nuke 9.1.x and lower.")
    func removeData(for key: String) {}
}

public extension DataLoading {
    // Deprecated in 9.2
    @available(*, deprecated, message: "This method exists for backward-compatibility with Nuke 9.1.x and lower.")
    func removeData(for request: URLRequest) {}
}
