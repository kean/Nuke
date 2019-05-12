// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

@available(*, deprecated, message: "Please use ImageScalingProcessor to resize images and ImagePipeline.Configuration.isDecompressionEnabled to control decompression (enabled by default)")
public typealias ImageDecompressor = ImageScalingProcessor
