// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A task that gets something from outside of the pipeline: the data from the
/// data loader, or the result of an async closure of the request. It's the only
/// work that can fail for a reason that goes away, so it's where retries are.
///
/// The retries are in the task, not in ``ImageTask``, for the sake of what
/// shares the work. Twenty cells showing the same avatar wait on one fetch, so
/// they get one sequence of retries instead of twenty, the retries of a request
/// reach everything that depends on it, and the tasks that join in the middle
/// of it wait along with the rest.
///
/// An attempt ends before the wait for the next one starts: a task that is
/// waiting holds no slot in ``ImagePipeline/Configuration-swift.struct/dataLoadingQueue``.
/// Each attempt then goes through ``start()``, so it gets back in the queue at
/// the current priority, and asks
/// ``ImagePipeline/Delegate-swift.protocol/willLoadData(for:urlRequest:pipeline:)``
/// for the request, which is what picks up a token refreshed in between.
class AsyncFetchTask<Value: Sendable>: AsyncPipelineTask<Value> {
    /// The number of retries so far. It changes when a retry starts, so it
    /// also tells the callbacks of an attempt that is over from the current
    /// one.
    private(set) var retryCount = 0
    private var retryTask: Task<Void, Never>?

    /// Fails the task or schedules a retry, and in either case ends the attempt.
    ///
    /// The caller is in the queue operation of the attempt, and returning from
    /// it gives the slot back, which is why the wait isn't awaited here.
    func attemptDidFail(with error: ImagePipeline.Error, response: URLResponse? = nil) {
        guard !isDisposed else { return }
        let policy = retryPolicy()
        guard policy != nil || !pipeline.isDefaultDelegate else {
            return send(error: error)
        }
        let context = ImagePipeline.RetryContext(request: request, error: error, response: response, retryCount: retryCount, policy: policy)
        onCancelled = { [weak self] in
            self?.retryTask?.cancel()
        }
        retryTask = Task { @ImagePipelineActor in
            await self.retry(context)
        }
    }

    private func retry(_ context: ImagePipeline.RetryContext) async {
        let decision = await pipeline.retryDecision(for: context)
        guard !isDisposed else { return }

        let delay: TimeInterval
        let connectivityTimeout: TimeInterval?
        switch decision {
        case .stop:
            return send(error: context.error)
        case .retry(let after):
            (delay, connectivityTimeout) = (after, nil)
        case let .retryWhenOnline(after, timeout):
            (delay, connectivityTimeout) = (after, timeout)
        }

        forEachImageTask { $0._isWaitingForRetry = true }
        let stage = diagnostics?.beginStage(.retryDelay)
        await Task.sleep(seconds: delay)
        var isOnline = true
        if let connectivityTimeout, !isDisposed {
            isOnline = await pipeline.connectivityMonitor.waitUntilOnline(timeout: connectivityTimeout)
        }
        diagnostics?.endStage(stage)
        forEachImageTask { $0._isWaitingForRetry = false }
        guard !isDisposed else { return }
        guard isOnline else {
            return send(error: context.error)
        }
        // Counted here and not when it's scheduled: a wait that is cut short
        // leaves a load that was only ever attempted once.
        retryTask = nil
        retryCount += 1
        forEachImageTask { $0._didRetry() }
        start()
    }

    private func forEachImageTask(_ body: (ImageTask) -> Void) {
        _ = containsImageTask {
            body($0)
            return false // Reaches every task
        }
    }

    /// Returns the policy that allows the most retries among the requests that
    /// wait for this task, or `nil` if none of them has a policy.
    ///
    /// A shared load keeps going for as long as one of the requests wants it
    /// to, the others get an image a little later. The alternative is to treat
    /// requests with different policies as different work, and keeping the
    /// policy out of the task keys costs nothing until something fails.
    ///
    /// Prefetching doesn't use the policy of the pipeline. It's speculative, and
    /// a load that matters is going to come with its own retries, or to join
    /// this one, in which case the policy applies.
    private func retryPolicy() -> ImagePipeline.RetryPolicy? {
        let pipelinePolicy = pipeline.configuration.retryPolicy
        var policy: ImagePipeline.RetryPolicy?
        forEachImageTask { task in
            let candidate = task.request.retryPolicy ?? (task._kind == .prefetch ? nil : pipelinePolicy)
            if let candidate, candidate.maxRetryCount > policy?.maxRetryCount ?? -1 {
                policy = candidate
            }
        }
        return policy
    }
}
