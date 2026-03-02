// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A global actor that serializes access to ``ImagePipeline`` and its
/// internal task graph. All pipeline coordination — starting, cancelling,
/// and coalescing image tasks, updating priorities, and delivering
/// delegate callbacks — runs on this actor.
///
/// Heavy work such as decoding, processing, and decompression is *not*
/// performed on this actor.
@globalActor public actor ImagePipelineActor {
    public static let shared = ImagePipelineActor()
}
