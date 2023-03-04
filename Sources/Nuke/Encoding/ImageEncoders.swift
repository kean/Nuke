// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A namespace with all available encoders.
public enum ImageEncoders {}

extension ImageEncoding where Self == ImageEncoders.Default {
    public static func `default`(compressionQuality: Float = 0.8) -> ImageEncoders.Default {
        ImageEncoders.Default(compressionQuality: compressionQuality)
    }
}

extension ImageEncoding where Self == ImageEncoders.ImageIO {
    public static func imageIO(type: AssetType, compressionRatio: Float = 0.8) -> ImageEncoders.ImageIO {
        ImageEncoders.ImageIO(type: type, compressionRatio: compressionRatio)
    }
}
