// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// The log the pipeline emits its signposts to.
let signpostLog = OSLog(subsystem: "com.github.kean.Nuke.ImagePipeline", category: "Image Loading")

extension ImagePipeline.Diagnostics.Stage {
    /// The name of the `os_signpost` interval the pipeline emits for the
    /// stage: the ``Kind`` it is, and whether it worked on a preview. The
    /// Instruments app aggregates the intervals by name, and a preview is
    /// decoded, processed, and decompressed on a different scale than the
    /// image, so the two are worth counting apart.
    ///
    /// `nil` for the stages that aren't worth an interval: the memory cache,
    /// which is over in less time than an interval costs to emit, and the
    /// rate limiter, which is recorded once it's already over. Everything
    /// else the diagnostics bracket is traced.
    ///
    /// The names spell out ``Kind`` again because `os_signpost` takes a
    /// `StaticString`, which a raw value isn't.
    var signpostName: StaticString? {
        switch kind {
        case .diskLookup: "diskLookup"
        case .willLoadData: "willLoadData"
        case .download: "download"
        case .diskStore: "diskStore"
        case .decode: isProgressive == true ? "decodePreview" : "decode"
        case .process: isProgressive == true ? "processPreview" : "process"
        case .decompress: isProgressive == true ? "decompressPreview" : "decompress"
        case .memoryLookup, .memoryStore, .rateLimit, .unknown: nil
        }
    }

    /// What the interval closes with, in the words the ``ImageTask/Metrics``
    /// timeline uses for the row of the same stage: `"network · 317 KB ·
    /// HTTP 200"`, `"ImageDecoders.Default · jpeg 640×480"`.
    var signpostMessage: String {
        details.joined(separator: " · ")
    }
}
