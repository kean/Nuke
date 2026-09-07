// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// The log the pipeline emits its signposts to.
let signpostLog = OSLog(subsystem: "com.github.kean.Nuke.ImagePipeline", category: "Image Loading")

extension ImagePipeline.Diagnostics.Stage {
    /// The name of the `os_signpost` interval the pipeline emits for the
    /// stage, or `nil` for a stage it doesn't trace.
    ///
    /// The traced stages are the work: the download, the decoding, the
    /// processing, and the decompression. The lookups and the waits are in
    /// the ``ImageTask/Metrics`` record, which is where they read better than
    /// as a row of hairlines in a trace.
    ///
    /// - important: The name has to be the same at both ends of the interval,
    /// so it's decided by ``kind`` and ``isProgressive``, which are set when
    /// the stage begins and never change.
    var signpostName: StaticString? {
        switch kind {
        case .download: "LoadImageData"
        case .decode: isProgressive == true ? "DecodeProgressiveImageData" : "DecodeImageData"
        case .process: isProgressive == true ? "ProcessProgressiveImage" : "ProcessImage"
        case .decompress: isProgressive == true ? "DecompressProgressiveImage" : "DecompressImage"
        default: nil
        }
    }

    /// What the stage produced, for the message of its closing signpost,
    /// such as `"network · 317 KB"` or `"jpeg · 1350×900"`.
    var signpostMessage: String {
        var parts: [String] = []
        if let source {
            parts.append(source.rawValue)
        }
        if let format {
            parts.append(format)
        }
        if let pixels {
            parts.append("\(pixels.width)×\(pixels.height)")
        }
        if let bytes {
            var text = Formatter.bytes(bytes)
            if let resumedBytes, resumedBytes > 0 {
                text += " (\(Formatter.bytes(resumedBytes)) resumed)"
            }
            parts.append(text)
        }
        return parts.joined(separator: " · ")
    }
}

/// Emits an `os_signpost` interval around the work.
///
/// The pipeline brackets the stages of a job itself – see
/// ``ImagePipeline/Diagnostics-swift.struct/Stage``. This is for the work that
/// isn't one of them: the image encoding, which a job schedules and doesn't
/// wait for.
func signpost<T>(_ name: StaticString, isEnabled: Bool, _ work: () -> T) -> T {
    guard isEnabled, signpostLog.signpostsEnabled else { return work() }

    let signpostID = OSSignpostID(log: signpostLog)
    os_signpost(.begin, log: signpostLog, name: name, signpostID: signpostID)
    defer { os_signpost(.end, log: signpostLog, name: name, signpostID: signpostID) }
    return work()
}
