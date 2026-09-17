// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import os

/// A ``DataLoading`` that loads through another loader under
/// ``DemoNetworkConditions``: late, at a capped rate, or not at all.
///
/// `DemoPipelineProbe` returns one for every download while the conditions
/// are on, around the loader the pipeline would have used, with the
/// conditions of that moment. For each download it:
///
/// 1. waits the latency, give or take the jitter, before the loader starts;
/// 2. fails a lost download with `URLError(.timedOut)`, and a server error
///    with `DataLoader.Error.statusCodeUnacceptable(500)` – the error
///    `DataLoader`'s validation fails a 500 with, before any data – without
///    starting the loader;
/// 3. passes the loader's chunks on, in slices no faster than the shared
///    bandwidth, with the loader's own response, so progress and previews
///    see the full expected length;
/// 4. cuts a truncated download off where it was drawn to, cancels the
///    loader, and fails with `URLError(.networkConnectionLost)`. The pipeline
///    keeps the part it got as resumable data if the response allows it, so
///    the next attempt asks for the rest – through the rig again.
///
/// A request that the `URLCache` of a `DataLoader` has a response for goes
/// through untouched, since the cache is on the device and the rig stands for
/// the network. The rig can't tell a response that is still fresh from one
/// the session will revalidate, so both skip the conditions.
///
/// **Contract.** `completion` is called once for every load, a cancelled one
/// included, and nothing is called after it. A cancel is passed to the loader
/// at once, and the load completes with `URLError(.cancelled)` then and
/// there, whatever the loader does: the pipeline frees a data loading slot
/// only when a load completes. So while the conditions are on, a loader that
/// goes quiet on cancel – ``ThrottledDataLoader``, as the documentation of
/// `DataLoading` asks – holds no slot.
///
/// **What it costs the figures.** The pipeline asks a `DataLoader` for its
/// `URLSession` metrics by a cast, which the rig fails, so a pipeline that
/// records diagnostics has none for conditioned downloads. The probe loses
/// nothing: it counts each conditioned download where the pipeline sees it –
/// its time to first byte includes the latency – and the session observer of
/// the `DataLoader` behind it still reports `URLCache` answers and reused
/// connections for it, without counting it twice.
///
/// **Draws.** Each download draws its jitter, its fate, and where it is cut
/// once, when it starts. With `-demoDeterministic 1` the draws come from a
/// generator seeded by the URL and the number of times it was loaded before,
/// so a run fails the same downloads whatever order they start in;
/// ``resetStatistics()`` starts the count over.
final class DemoConditionedDataLoader: DataLoading, Sendable {
    /// The loader the downloads go through.
    let base: any DataLoading
    let profile: DemoNetworkConditions.Profile
    /// The cache a `DataLoader`'s session answers from before the network.
    private let urlCache: URLCache?

    init(_ base: any DataLoading, profile: DemoNetworkConditions.Profile) {
        self.base = base
        self.profile = profile
        self.urlCache = (base as? DataLoader)?.session.configuration.urlCache
    }

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let load = Load(
            base: base,
            request: request,
            plan: Plan(profile: profile, url: request.url),
            bandwidth: profile.bandwidth,
            urlCache: urlCache,
            didReceiveData: didReceiveData,
            completion: completion
        )
        load.start()
        return load
    }
}

// MARK: - Statistics

extension DemoConditionedDataLoader {
    /// What the rig has done to the downloads of every pipeline since the last
    /// reset.
    struct Statistics: Sendable {
        /// Downloads that started under the conditions.
        var loadCount = 0
        /// Downloads started and not yet completed.
        var inFlightCount = 0
        /// Downloads that went through untouched because `URLCache` had a
        /// response for them.
        var passedToURLCacheCount = 0
        /// The latency drawn for each download, in seconds.
        var latency = DemoPipelineDiagnostics.Timing()
        /// The seconds chunks waited for the shared link after they arrived
        /// from the loader, added up.
        var bandwidthWait: TimeInterval = 0
        /// The bytes passed on to the pipelines.
        var deliveredByteCount: Int64 = 0
        /// Downloads failed with `URLError(.timedOut)`.
        var lostCount = 0
        /// Downloads failed with a 500.
        var serverErrorCount = 0
        /// Downloads cut off with `URLError(.networkConnectionLost)`.
        var truncatedCount = 0
        /// The bytes the cut-off downloads delivered before the cut.
        var truncatedByteCount: Int64 = 0
        /// Downloads the loader completed.
        var completedCount = 0
        /// Downloads the loader failed on its own, such as a real 404.
        var failedCount = 0
        /// Downloads cancelled before they completed.
        var cancelledCount = 0
    }

    /// A copy of the statistics: a lock and a copy, fine to sample on a timer.
    static var statistics: Statistics {
        shared.withLock { $0.statistics }
    }

    /// Starts the statistics over, and the count of loads per URL the
    /// deterministic draws are seeded with. Downloads in flight stay counted
    /// as in flight.
    static func resetStatistics() {
        shared.withLock { shared in
            var statistics = Statistics()
            statistics.inFlightCount = shared.statistics.inFlightCount
            shared.statistics = statistics
            shared.attempts = [:]
        }
    }

    private static let shared = OSAllocatedUnfairLock(initialState: Shared())

    private struct Shared: Sendable {
        var statistics = Statistics()
        /// The loads of each URL so far, for the deterministic draws.
        var attempts: [String: UInt64] = [:]
        /// When the shared link is free to carry the next slice.
        var linkFreeAt: ContinuousClock.Instant?
    }

    fileprivate static func record(_ update: @Sendable (inout Statistics) -> Void) {
        shared.withLock { update(&$0.statistics) }
    }

    /// Books the next slice on the link every conditioned download shares and
    /// returns when it has gone through: slices from all the downloads take
    /// turns, so together they get no more than the bandwidth.
    fileprivate static func reserveLink(byteCount: Int, bandwidth: Int) -> ContinuousClock.Instant {
        let now = ContinuousClock.now
        let duration = Duration.seconds(Double(byteCount) / Double(bandwidth))
        return shared.withLock { shared in
            let start = max(shared.linkFreeAt ?? now, now)
            shared.linkFreeAt = start + duration
            return start + duration
        }
    }

    /// The generator for the next load of `url`: seeded at random, or, with
    /// `-demoDeterministic 1`, by the URL and the attempt.
    fileprivate static func makeGenerator(for url: URL?) -> DemoRandomNumberGenerator {
        guard DemoLaunchOptions.current.isDeterministic else {
            return DemoRandomNumberGenerator(seed: .random(in: .min ... .max))
        }
        let key = url?.absoluteString ?? ""
        let attempt = shared.withLock { shared in
            defer { shared.attempts[key, default: 0] += 1 }
            return shared.attempts[key, default: 0]
        }
        return DemoRandomNumberGenerator(seed: fnv1a(key) ^ (attempt &* 0x9E37_79B9_7F4A_7C15))
    }

    /// FNV-1a: a hash that, unlike `Hasher`, is the same in every process.
    private static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in string.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100_0000_01B3
        }
        return hash
    }
}

// MARK: - Load

/// What a download was drawn to go through.
private struct Plan: Sendable {
    enum Fault: Sendable {
        case loss
        case serverError
        /// Cut off at this share of the body.
        case truncation(Double)
    }

    let latency: Duration
    let fault: Fault?

    init(profile: DemoNetworkConditions.Profile, url: URL?) {
        var generator = DemoConditionedDataLoader.makeGenerator(for: url)
        // Every draw is made whatever the rates, so a download's numbers
        // don't depend on them.
        let jitter = Double.random(in: -1...1, using: &generator)
        let loss = Double.random(in: 0..<1, using: &generator)
        let serverError = Double.random(in: 0..<1, using: &generator)
        let truncation = Double.random(in: 0..<1, using: &generator)
        let cut = Double.random(in: 0.2...0.8, using: &generator)

        latency = max(.zero, profile.latency + profile.jitter * jitter)
        if loss < profile.lossRate {
            fault = .loss
        } else if serverError < profile.serverErrorRate {
            fault = .serverError
        } else if truncation < profile.truncationRate {
            fault = .truncation(cut)
        } else {
            fault = nil
        }
    }
}

/// One download: a task that runs the plan, and a lock that makes sure
/// `completion` is called once and nothing after it, whichever of the task,
/// the loader, and a cancel gets there first.
private final class Load: Cancellable, Sendable {
    private let base: any DataLoading
    private let request: URLRequest
    private let plan: Plan
    private let bandwidth: Int?
    private let urlCache: URLCache?
    private let didReceiveData: @Sendable (Data, URLResponse) -> Void
    private let completion: @Sendable (Error?) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    private struct State: Sendable {
        var isFinished = false
        var baseLoad: (any Cancellable)?
        var task: Task<Void, Never>?
    }

    private enum Outcome: Sendable {
        case completed
        case failed
        case lost
        case serverError
        case truncated(Int64)
        case cancelled
    }

    private enum Event: Sendable {
        case data(Data, URLResponse)
        case completed(Error?)
    }

    init(
        base: any DataLoading,
        request: URLRequest,
        plan: Plan,
        bandwidth: Int?,
        urlCache: URLCache?,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) {
        self.base = base
        self.request = request
        self.plan = plan
        self.bandwidth = bandwidth
        self.urlCache = urlCache
        self.didReceiveData = didReceiveData
        self.completion = completion
    }

    func start() {
        let latency = plan.latency.demoTimeInterval
        DemoConditionedDataLoader.record { statistics in
            statistics.loadCount += 1
            statistics.inFlightCount += 1
        }
        let task = Task {
            await run(latency: latency)
        }
        let isFinished = state.withLock { state in
            guard !state.isFinished else { return true }
            state.task = task
            return false
        }
        if isFinished {
            task.cancel()
        }
    }

    func cancel() {
        finish(URLError(.cancelled), .cancelled)
    }

    private func run(latency: TimeInterval) async {
        do {
            // Off the pipeline's actor: a lookup can read the disk.
            if let urlCache, request.cachePolicy != .reloadIgnoringLocalCacheData,
               urlCache.cachedResponse(for: request) != nil {
                DemoConditionedDataLoader.record { $0.passedToURLCacheCount += 1 }
                try await load(isConditioned: false)
                return
            }
            DemoConditionedDataLoader.record { $0.latency.record(latency, at: .now) }
            try await Task.sleep(for: plan.latency)
            switch plan.fault {
            case .loss:
                finish(urlError(.timedOut, "The request timed out."), .lost)
            case .serverError:
                finish(DataLoader.Error.statusCodeUnacceptable(500), .serverError)
            case .truncation, nil:
                try await load(isConditioned: true)
            }
        } catch {
            // Only a cancel stops a sleep, and it has completed the load.
        }
    }

    /// Starts the loader and passes on what it sends, until it completes or
    /// the plan cuts it off.
    private func load(isConditioned: Bool) async throws {
        let (events, continuation) = AsyncStream.makeStream(of: Event.self)
        let baseLoad = base.loadData(with: request) { data, response in
            continuation.yield(.data(data, response))
        } completion: { error in
            continuation.yield(.completed(error))
            continuation.finish()
        }
        let isFinished = state.withLock { state in
            guard !state.isFinished else { return true }
            state.baseLoad = baseLoad
            return false
        }
        guard !isFinished else {
            // Cancelled while the loader was starting.
            baseLoad.cancel()
            return
        }

        var cutOffset: Int?
        var delivered: Int64 = 0
        // Ends early if the task is cancelled, which only a cancel does.
        for await event in events {
            switch event {
            case .data(var data, let response):
                var isCut = false
                if isConditioned, case .truncation(let share) = plan.fault {
                    let offset = cutOffset ?? Self.cutOffset(at: share, of: response, firstChunk: data.count)
                    cutOffset = offset
                    let remaining = offset - Int(delivered)
                    if data.count >= remaining {
                        data = data.prefix(max(0, remaining))
                        isCut = true
                    }
                }
                try await deliver(data, response, isConditioned: isConditioned)
                delivered += Int64(data.count)
                if isCut {
                    finish(urlError(.networkConnectionLost, "The network connection was lost."), .truncated(delivered))
                    return
                }
            case .completed(let error):
                finish(error, error == nil ? .completed : .failed)
                return
            }
        }
    }

    /// The error `URLSession` fails a task with, with the description and URL
    /// it gives one, so the app reads the same thing either way.
    private func urlError(_ code: URLError.Code, _ description: String) -> URLError {
        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: description]
        if let url = request.url {
            userInfo[NSURLErrorFailingURLErrorKey] = url
            userInfo[NSURLErrorFailingURLStringErrorKey] = url.absoluteString
        }
        return URLError(code, userInfo: userInfo)
    }

    /// Where a body is cut: at `share` of the length the response expects, or
    /// halfway through the first chunk when it doesn't say.
    private static func cutOffset(at share: Double, of response: URLResponse, firstChunk: Int) -> Int {
        let expected = response.expectedContentLength
        guard expected > 0 else {
            return max(1, firstChunk / 2)
        }
        return max(1, Int(Double(expected) * share))
    }

    /// Passes a chunk on: at once, or in slices of a tenth of a second of the
    /// shared link.
    private func deliver(_ data: Data, _ response: URLResponse, isConditioned: Bool) async throws {
        guard isConditioned, let bandwidth, bandwidth > 0 else {
            send(data, response)
            return
        }
        let sliceSize = max(512, bandwidth / 10)
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = min(offset + sliceSize, data.endIndex)
            let arrivedAt = ContinuousClock.now
            let deadline = DemoConditionedDataLoader.reserveLink(byteCount: end - offset, bandwidth: bandwidth)
            try await Task.sleep(until: deadline, clock: .continuous)
            let wait = (deadline - arrivedAt).demoTimeInterval
            DemoConditionedDataLoader.record { $0.bandwidthWait += wait }
            guard send(data[offset..<end], response) else { return }
            offset = end
        }
    }

    /// Calls `didReceiveData` unless the load has completed. Under the lock,
    /// so a cancel on another thread can't complete the load in between.
    @discardableResult
    private func send(_ data: Data, _ response: URLResponse) -> Bool {
        guard !data.isEmpty else { return true }
        let isSent = state.withLock { state in
            guard !state.isFinished else { return false }
            didReceiveData(data, response)
            return true
        }
        if isSent {
            let count = Int64(data.count)
            DemoConditionedDataLoader.record { $0.deliveredByteCount += count }
        }
        return isSent
    }

    /// Calls `completion`, once, and lets go of the loader and the task.
    private func finish(_ error: Error?, _ outcome: Outcome) {
        let running = state.withLock { state -> (baseLoad: (any Cancellable)?, task: Task<Void, Never>?)? in
            guard !state.isFinished else { return nil }
            state.isFinished = true
            completion(error)
            defer {
                state.baseLoad = nil
                state.task = nil
            }
            return (state.baseLoad, state.task)
        }
        guard let running else { return }
        switch outcome {
        case .cancelled:
            running.baseLoad?.cancel()
            running.task?.cancel()
        case .truncated:
            running.baseLoad?.cancel()
        default:
            break
        }
        DemoConditionedDataLoader.record { statistics in
            statistics.inFlightCount -= 1
            switch outcome {
            case .completed: statistics.completedCount += 1
            case .failed: statistics.failedCount += 1
            case .lost: statistics.lostCount += 1
            case .serverError: statistics.serverErrorCount += 1
            case .truncated(let byteCount):
                statistics.truncatedCount += 1
                statistics.truncatedByteCount += byteCount
            case .cancelled: statistics.cancelledCount += 1
            }
        }
    }
}
