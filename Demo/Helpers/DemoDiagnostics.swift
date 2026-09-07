// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import OSLog

/// Logs where the time of every image task went, when the app is launched
/// with the `NUKE_DIAGNOSTICS_ENABLED` environment variable set.
///
/// The variable is in the NukeDemo scheme, unticked: Edit Scheme › Run ›
/// Arguments › Environment Variables. Every task then finishes with a
/// timeline in Console, under the `com.github.kean.NukeDemo` subsystem:
///
/// ```
/// xcrun simctl spawn booted log stream --predicate 'subsystem == "com.github.kean.NukeDemo"'
/// ```
///
/// The switch itself lives in Nuke — see
/// ``ImagePipeline/Diagnostics-swift.struct/isEnabledByEnvironment`` — so
/// every pipeline records with it set, whether or not it passes ``delegate``
/// to `ImagePipeline.init`.
enum DemoDiagnostics {
    private static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "ImageTask")

    /// Pass this to `ImagePipeline.init(delegate:)` so the pipeline logs
    /// every finished task to Console. `nil` when the switch is off, which
    /// leaves the pipeline on its default delegate.
    static let delegate: (any ImagePipeline.Delegate)? = ImagePipeline.Diagnostics.isEnabledByEnvironment ? DiagnosticsLogger() : nil

    /// Logs the record of a finished task. A pipeline with a delegate of its
    /// own calls this from `imageTask(_:didReceiveEvent:pipeline:)`.
    static func log(_ task: ImageTask) {
        guard let metrics = task.metrics else { return }
        let level: OSLogType = switch metrics.outcome {
        case .failure: .error
        case .cancelled: .info
        default: .default
        }
        logger.log(level: level, "\(metrics.description, privacy: .public)")
    }
}

/// Logs every task of a pipeline when it finishes.
private final class DiagnosticsLogger: ImagePipeline.Delegate {
    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished = event else { return }
        DemoDiagnostics.log(task)
    }
}
