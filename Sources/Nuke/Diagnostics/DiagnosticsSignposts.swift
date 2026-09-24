// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

// The records send an `os_signpost` interval for every task, job, and stage
// they record, so Instruments shows the same timeline as ``ImageTask/Metrics``.

extension ImagePipeline.Diagnostics {
    /// The default ``ImagePipeline/Configuration-swift.struct/signpostLog``.
    static let defaultSignpostLog = OSLog(subsystem: "com.github.kean.Nuke.ImagePipeline", category: "Image Loading")
}

extension ImagePipeline.Diagnostics.Job.Kind {
    var signpostName: StaticString {
        switch self {
        case .loadImage: "LoadImage"
        case .fetchOriginalImage: "FetchOriginalImage"
        case .fetchOriginalData: "FetchOriginalData"
        case .loadData: "LoadData"
        case .unknown: "Job"
        }
    }
}

extension ImagePipeline.Diagnostics.Stage.Kind {
    var signpostName: StaticString {
        switch self {
        case .memoryLookup: "MemoryLookup"
        case .diskLookup: "DiskLookup"
        case .rateLimit: "RateLimit"
        case .willLoadData: "WillLoadData"
        case .download: "Download"
        case .diskStore: "DiskStore"
        case .decode: "Decode"
        case .process: "Process"
        case .decompress: "Decompress"
        case .memoryStore: "MemoryStore"
        case .unknown: "Stage"
        }
    }
}

extension ImagePipeline.Diagnostics.Stage {
    /// What the stage did, such as `"network · 12 KB · HTTP 200"`, for the
    /// end of its interval.
    var signpostMessage: String {
        var parts: [String] = []
        if isProgressive == true {
            parts.append("preview")
        }
        parts += [result?.rawValue, source?.rawValue].compactMap { $0 }
        if let bytes {
            parts.append(Formatter.bytes(bytes))
        }
        if let resumedBytes, resumedBytes > 0 {
            parts.append("\(Formatter.bytes(resumedBytes)) resumed")
        }
        parts += [
            statusCode.map { "HTTP \($0)" },
            decoder,
            processor,
            format,
            pixels.map { "\($0.width)×\($0.height)" }
        ].compactMap { $0 }
        return parts.joined(separator: " · ")
    }
}

extension ImageRequest {
    /// The request as the signposts describe it: the URL, or the image ID of
    /// a closure, and the processors.
    var signpostMessage: String {
        var text = url?.absoluteString ?? imageID ?? ""
        if !processors.isEmpty {
            text += " · " + processors.map(\.identifier).joined(separator: ", ")
        }
        return text
    }
}
