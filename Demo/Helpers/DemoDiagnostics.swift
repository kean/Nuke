// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import OSLog

/// Logs where the time of every image task went, when the app is launched
/// with the `NUKE_DIAGNOSTICS` environment variable set.
///
/// The variable is in the NukeDemo scheme, unticked: Edit Scheme › Run ›
/// Arguments › Environment Variables. Every task then finishes with a
/// timeline in Console, under the `com.github.kean.NukeDemo` subsystem:
///
/// ```
/// xcrun simctl spawn booted log stream --predicate 'subsystem == "com.github.kean.NukeDemo"'
/// ```
///
/// Every pipeline in the demo is made through ``makePipeline(_:)`` or
/// ``makePipeline(configuration:)``, so the switch covers every screen.
enum DemoDiagnostics {
    /// `true` if the app was launched with `NUKE_DIAGNOSTICS` set.
    static let isEnabled = ProcessInfo.processInfo.environment["NUKE_DIAGNOSTICS"] != nil

    private static let logger = Logger(subsystem: "com.github.kean.NukeDemo", category: "ImageTask")

    /// The delegate that logs the records, or `nil` when the switch is off,
    /// which leaves the pipeline on its default delegate.
    private static let delegate: (any ImagePipeline.Delegate)? = isEnabled ? DiagnosticsLogger() : nil

    /// `ImagePipeline.init(_:)`, with the diagnostics on and the records
    /// logged when the switch is set.
    static func makePipeline(_ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline(delegate: delegate) {
            $0.isDiagnosticsEnabled = isEnabled
            configure(&$0)
        }
    }

    /// `ImagePipeline.init(configuration:)`, with the diagnostics on and the
    /// records logged when the switch is set.
    static func makePipeline(configuration: ImagePipeline.Configuration) -> ImagePipeline {
        var configuration = configuration
        configuration.isDiagnosticsEnabled = isEnabled
        return ImagePipeline(configuration: configuration, delegate: delegate)
    }

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
