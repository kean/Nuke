// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    /// How long the pipeline stops requesting a URL after the server said the
    /// image isn't there, and which responses say so.
    ///
    /// Set it with ``ImagePipeline/Configuration-swift.struct/failureCooldown``.
    public struct FailureCooldown: Sendable {
        /// How long a URL stays in cooldown after the failure, in seconds.
        public var duration: TimeInterval

        /// The HTTP status codes that put a URL in cooldown. `404` and `410` by
        /// default.
        ///
        /// Think twice before adding to it. `401` and `403` end when a token is
        /// refreshed, and `429` and the `5xx` codes when the server recovers, so
        /// none of them say anything about the URL.
        ///
        /// The pipeline reads the code from
        /// ``DataLoader/Error/statusCodeUnacceptable(_:)``, which is what
        /// ``DataLoader`` reports by default. A custom ``DataLoading``, or a
        /// custom `validate` closure, has to report the same error for a URL to
        /// enter the cooldown.
        public var statusCodes: Set<Int>

        // Keeps running while the device sleeps, and doesn't follow the system
        // date, which would stretch the window by however far it moved back.
        var now: @Sendable () -> TimeInterval = {
            TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
        }

        /// Initializes the cooldown with the given duration.
        ///
        /// - parameters:
        ///   - duration: How long a URL stays in cooldown after the failure, in
        ///   seconds.
        ///   - statusCodes: The HTTP status codes that put a URL in cooldown.
        public init(duration: TimeInterval, statusCodes: Set<Int> = [404, 410]) {
            self.duration = duration
            self.statusCodes = statusCodes
        }
    }

    /// Takes every URL out of the cooldown, so the next load of each of them
    /// reaches the data loader. Does nothing if
    /// ``ImagePipeline/Configuration-swift.struct/failureCooldown`` isn't set.
    ///
    /// Use it when something happened that can bring the images back, such as
    /// the user signing in to another account. To retry one image, use
    /// ``ImageRequest/Options-swift.struct/skipFailureCooldown``.
    public func resetFailureCooldown() {
        failureRegistry?.removeAll()
    }
}

/// The URLs in cooldown. It has no lock because the fetch tasks that use it all
/// run on the pipeline's actor, and it's a class of its own so that a pipeline
/// with no cooldown pays for one `nil` check per download and nothing else.
@ImagePipelineActor
final class FailureRegistry {
    /// Enough for the dead URLs of a long feed, at a few hundred bytes each. A
    /// URL pushed out by it is only requested again sooner than it had to be.
    nonisolated static var countLimit: Int { 1024 }

    private struct Entry {
        let error: any Error
        let expiresAt: TimeInterval
    }

    private let cooldown: ImagePipeline.FailureCooldown
    private var entries: [String: Entry] = [:]

    var count: Int { entries.count }

    nonisolated init(cooldown: ImagePipeline.FailureCooldown) {
        self.cooldown = cooldown
    }

    /// Returns the failure that put the URL of the request in cooldown, or `nil`
    /// if the request can go ahead.
    func failure(for request: ImageRequest) -> (any Error)? {
        // The key is the URL and not the image ID: a custom `imageID` says what
        // to call the image, and it's the URL that is gone.
        guard !entries.isEmpty, let key = request.originalImageID, let entry = entries[key] else {
            return nil
        }
        guard !request.options.contains(.skipFailureCooldown), !request.options.contains(.reloadIgnoringCachedData) else {
            return nil
        }
        guard entry.expiresAt > cooldown.now() else {
            entries[key] = nil
            return nil
        }
        return entry.error
    }

    /// Records how a download ended: a success takes the URL out of the
    /// cooldown, and a failure with one of the status codes starts it over.
    func didFinishLoading(_ request: ImageRequest, error: ImagePipeline.Error?) {
        guard let key = request.originalImageID else { return }
        guard let error else {
            entries[key] = nil
            return
        }
        guard case .statusCodeUnacceptable(let statusCode)? = error.dataLoadingError as? DataLoader.Error,
              cooldown.statusCodes.contains(statusCode) else {
            return
        }
        if entries.count >= Self.countLimit, entries[key] == nil {
            makeRoom()
        }
        entries[key] = Entry(error: DataLoader.Error.statusCodeUnacceptable(statusCode), expiresAt: cooldown.now() + cooldown.duration)
    }

    func removeAll() {
        entries.removeAll()
    }

    /// Drops what has expired, and failing that, what would have expired first.
    /// A scan: it only runs after a failed download, and only with a full
    /// registry, so a sorted structure wouldn't pay for itself.
    private func makeRoom() {
        let now = cooldown.now()
        entries = entries.filter { $0.value.expiresAt > now }
        if entries.count >= Self.countLimit, let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt }) {
            entries[oldest.key] = nil
        }
    }
}
