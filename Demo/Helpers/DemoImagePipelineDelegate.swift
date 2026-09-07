// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import OSLog

/// Logs where the time of every image task went. Every pipeline in the demo
/// installs it.
///
/// It logs what the pipeline recorded, and the recording is off until the app
/// is launched with the `NUKE_DIAGNOSTICS_ENABLED` environment variable set —
/// the switch lives in Nuke, see
/// ``ImagePipeline/Configuration-swift.struct/isDiagnosticsEnabled``. The
/// variable is in the NukeDemo scheme, unticked: Edit Scheme › Run › Arguments
/// › Environment Variables. Every task then finishes with a timeline in
/// Console, under the `com.github.kean.NukeDemo` subsystem:
///
/// ```
/// xcrun simctl spawn booted log stream --predicate 'subsystem == "com.github.kean.NukeDemo"'
/// ```
final class DemoImagePipelineDelegate: ImagePipeline.Delegate {
    private static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "ImageTask")

    @ImagePipelineActor
    func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
        guard case .finished = event else { return }
        Self.log(task)
    }

    /// Logs the record of a finished task, and nothing at all if the pipeline
    /// didn't record one. A pipeline with a delegate of its own calls this from
    /// `imageTask(_:didReceiveEvent:pipeline:)`.
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
