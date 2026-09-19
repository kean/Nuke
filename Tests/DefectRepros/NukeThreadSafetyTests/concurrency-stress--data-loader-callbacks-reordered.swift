// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation

// SUSPECTED BUG: the pipeline can drop the data a `DataLoading` delivered if
// the loader calls `didReceiveData` and `completion` from threads of different
// QoS classes.
//
// `TaskFetchOriginalData.loadData(with:dataLoader:)` forwards each callback to
// the pipeline actor with its own unstructured task:
//
//     didReceiveData: Task { @ImagePipelineActor in self?.dataTaskDidReceive(...) }
//     completion:     Task { @ImagePipelineActor in self?.finishDataLoad(...) }
//
// Those hops aren't ordered – the actor runs its queued jobs by priority – so a
// completion delivered from a higher-QoS thread overtakes a chunk delivered
// earlier from a lower-QoS thread. `finishDataLoad` then resumes the load with
// no data, and when the chunk's hop finally runs, `dataTaskDidReceive` finds
// `dataLoadContinuation == nil` and silently discards it. (Two chunks from
// different QoS classes can likewise be appended out of order.)
//
// Expected: a loader that honours the `DataLoading` contract – "completion:
// Must be called once after all ... `didReceiveData` closures have been
// called" – gets its image decoded, whatever threads it calls back on.
// Actual: the task fails with `ImagePipeline.Error.dataIsEmpty` ("Data loader
// returned empty data"). The same loader calling both closures at the same QoS
// succeeds (see `callbacksAtTheSameQoSSucceed`), which pins the cause on the
// reordering.
//
// The loader holds the pipeline actor while it calls back – standing in for an
// actor that is busy, which it routinely is while images load – so both hops
// are queued before either runs; that makes the reordering deterministic.
//
// Location: Sources/Nuke/Tasks/TaskFetchOriginalData.swift:150-171
// (the hops), :177 (the dropped chunk).
@Suite(.timeLimit(.minutes(5)))
struct DataLoaderCallbackReorderingRepro {
    @Test func dataDeliveredBeforeCompletionIsNotDropped() async {
        let pipeline = ImagePipeline {
            $0.dataLoader = QoSSplittingDataLoader(dataQoS: .background, completionQoS: .userInitiated)
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
        }
        do {
            _ = try await pipeline.image(for: Test.request)
        } catch {
            Issue.record("The load failed: \(error)") // Fails: dataIsEmpty
        }
    }

    /// Control: the same loader, both callbacks at the same QoS.
    @Test func callbacksAtTheSameQoSSucceed() async {
        let pipeline = ImagePipeline {
            $0.dataLoader = QoSSplittingDataLoader(dataQoS: .userInitiated, completionQoS: .userInitiated)
            $0.imageCache = nil
            $0.isRateLimiterEnabled = false
        }
        do {
            _ = try await pipeline.image(for: Test.request)
        } catch {
            Issue.record("The load failed: \(error)")
        }
    }
}

/// Calls `didReceiveData` on one QoS class and, after that call returned,
/// `completion` on another, while the pipeline actor is busy.
private final class QoSSplittingDataLoader: DataLoading, @unchecked Sendable {
    let dataQoS: DispatchQoS.QoSClass
    let completionQoS: DispatchQoS.QoSClass

    init(dataQoS: DispatchQoS.QoSClass, completionQoS: DispatchQoS.QoSClass) {
        self.dataQoS = dataQoS
        self.completionQoS = completionQoS
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Cancellable {
        let data = Test.data(name: "fixture", extension: "jpeg")
        let response = URLResponse(url: request.url!, mimeType: "jpeg", expectedContentLength: data.count, textEncodingName: nil)
        let (dataQoS, completionQoS) = (self.dataQoS, self.completionQoS)
        Thread.detachNewThread {
            let gate = holdPipelineActor()
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: dataQoS).async {
                didReceiveData(data, response)
                done.signal()
            }
            done.wait()
            DispatchQueue.global(qos: completionQoS).async {
                completion(nil)
                done.signal()
            }
            done.wait()
            gate.signal()
        }
        return NoopCancellable()
    }
}

private struct NoopCancellable: Cancellable {
    func cancel() {}
}

private func blockOnSemaphore(_ semaphore: DispatchSemaphore) { semaphore.wait() }

/// Occupies the pipeline actor until the returned semaphore is signalled.
private func holdPipelineActor() -> DispatchSemaphore {
    let entered = DispatchSemaphore(value: 0)
    let gate = DispatchSemaphore(value: 0)
    Task.detached { @ImagePipelineActor in
        entered.signal()
        blockOnSemaphore(gate)
    }
    entered.wait()
    return gate
}
