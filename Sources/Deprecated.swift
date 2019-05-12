// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Foundation

// Deprecated in Nuke 8.0. Remove by January 2020.
@available(*, deprecated, message: "Please use ImageScalingProcessor to resize images and ImagePipeline.Configuration.isDecompressionEnabled to control decompression (enabled by default)")
public typealias ImageDecompressor = ImageScalingProcessor
