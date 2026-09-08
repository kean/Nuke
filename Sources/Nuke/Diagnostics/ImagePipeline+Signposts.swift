// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// The log the pipeline emits its signposts to.
private let signpostLog = OSLog(subsystem: "com.github.kean.Nuke.ImagePipeline", category: "Image Loading")

extension ImagePipeline.Diagnostics {
    /// Publishes the stages of one job to the Instruments app, as
    /// `os_signpost` intervals.
    ///
    /// It exists only while something is collecting them: the initializer
    /// returns `nil` otherwise, and a job makes one and keeps it, so every
    /// interval it opens is also closed, whenever the collection stops.
    ///
    /// The intervals are paired by the C `os_signpost` rather than by
    /// `OSSignposter`, whose `beginInterval` hands back a state to hold until
    /// the interval ends – state every running stage would have to carry.
    struct Signposter {
        /// Shared by every interval of the job. The stages of a job that map
        /// to one name never overlap, so one id is enough to tell the jobs
        /// apart in a trace.
        private let id: OSSignpostID
        /// The image the job is for, for the message of an opening interval.
        private let label: String

        init?(request: ImageRequest) {
            guard signpostLog.signpostsEnabled else { return nil }
            self.id = OSSignpostID(log: signpostLog)
            self.label = request.url?.absoluteString ?? ""
        }

        /// Opens the interval of a stage that is starting, if it has one.
        func begin(_ stage: Stage) {
            guard let name = stage.signpostName else { return }
            os_signpost(.begin, log: signpostLog, name: name, signpostID: id, "%{public}s", label)
        }

        /// Closes the interval of a stage that was running, if it has one,
        /// with what the stage did – or with why the job stopped it.
        func end(_ stage: Stage, _ message: String? = nil) {
            guard let name = stage.signpostName else { return }
            os_signpost(.end, log: signpostLog, name: name, signpostID: id, "%{public}s", message ?? stage.signpostMessage)
        }
    }
}

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
    ///
    /// - important: A job emits every interval under one signpost id, so a
    /// name has to be the same at both ends of an interval, and two stages of
    /// the same name must never overlap. Splitting the preview off is what
    /// keeps the second half true: a preview decode that was cancelled can
    /// still be running when the decode of the image begins.
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
