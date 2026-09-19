// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

@testable import Nuke
import Testing
import Foundation

// SUSPECTED BUG: a request created after `invalidate()` returned can still be
// served by the pipeline.
//
// `invalidate()` sets `isInvalidated` in an unstructured hop,
// `Task { @ImagePipelineActor in ... }`, and a new task is started by a hop of
// its own (`makeStartedImageTask`). The hops aren't ordered – the actor runs its
// queued jobs by priority – so when `invalidate()` is called from a lower-QoS
// thread than the one that creates the next task, the task's start overtakes the
// invalidation: `startImageTask` finds `isInvalidated == false` and runs the
// request. A memory cache hit then completes it successfully before the
// invalidation lands (a request that has to load data is cancelled a moment
// later instead, failing with `.cancelled` rather than `.pipelineInvalidated`).
//
// Expected (doc comment of `invalidate()`): "Any new requests will immediately
// fail with ``ImagePipeline/Error/pipelineInvalidated`` error."
// Actual: the task created after `invalidate()` returned succeeds with the
// cached image. The same sequence with both calls made at the same QoS fails
// with `.pipelineInvalidated`, as documented (`invalidateAtTheSameQoS`).
//
// The test holds the pipeline actor for a moment – standing in for an actor that
// is busy – so both hops are queued before either runs, which makes the
// reordering deterministic.
//
// Location: Sources/Nuke/Pipeline/ImagePipeline.swift:130-138 (`invalidate()`),
// :184 (the start hop), :205 (the `isInvalidated` check).
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineInvalidateOrderingRepro {
    @Test func requestCreatedAfterInvalidateFails() async {
        await checkRequestAfterInvalidate(invalidateQoS: .background) // Fails: succeeds
    }

    /// Control: the same sequence, both calls at the same QoS.
    @Test func invalidateAtTheSameQoS() async {
        await checkRequestAfterInvalidate(invalidateQoS: .userInitiated)
    }

    private func checkRequestAfterInvalidate(invalidateQoS: DispatchQoS.QoSClass) async {
        // Given an image in the memory cache
        let imageCache = ImageCache()
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = imageCache
        }
        imageCache[ImageCacheKey(request: Test.request)] = Test.container

        // When `invalidate()` returns, and only then a new task is created
        let task = invalidateThenCreateTask(pipeline, invalidateQoS: invalidateQoS)

        // Then
        do {
            _ = try await task.response
            Issue.record("A task created after invalidate() returned succeeded")
        } catch {
            #expect(error == .pipelineInvalidated)
        }
    }
}

private func blockOnSemaphore(_ semaphore: DispatchSemaphore) { semaphore.wait() }

private func invalidateThenCreateTask(_ pipeline: ImagePipeline, invalidateQoS: DispatchQoS.QoSClass) -> ImageTask {
    // Occupy the actor so that both hops are queued before either runs.
    let entered = DispatchSemaphore(value: 0)
    let gate = DispatchSemaphore(value: 0)
    Task.detached { @ImagePipelineActor in
        entered.signal()
        blockOnSemaphore(gate)
    }
    entered.wait()

    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global(qos: invalidateQoS).async {
        pipeline.invalidate()
        done.signal()
    }
    done.wait()
    nonisolated(unsafe) var task: ImageTask?
    DispatchQueue.global(qos: .userInitiated).async {
        task = pipeline.imageTask(with: Test.request)
        done.signal()
    }
    done.wait()
    gate.signal()
    return task!
}
