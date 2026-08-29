# Where Nuke's Work Runs

Learn which thread runs what, and how to change the limits.

## Overview

Nuke has exactly two places where work happens: ``ImagePipelineActor``, which serializes all coordination, and the cooperative thread pool, where the expensive CPU work runs. The five ``TaskQueue`` instances on the configuration decide how much of the latter runs at once.

You don't need any of this to load an image. You need it when you're writing a custom ``ImageProcessing``, an ``ImageDecoding``, or an ``ImagePipeline/Delegate-swift.protocol`` – or when the CPU work is competing with your app.

## ImagePipelineActor

``ImagePipelineActor`` is a global actor. Everything that touches the pipeline's task graph runs on it: starting and cancelling tasks, coalescing equivalent requests, updating priorities, reading and writing the memory cache, and delivering the delegate callbacks that report progress.

```swift
@ImagePipelineActor
final class RequestLog {
    private var started: [ImageTask.ID: Date] = [:]

    func record(_ task: ImageTask) {
        started[task.id] = Date() // No lock needed: the actor serializes access
    }
}
```

What does *not* run on it is the expensive part. Decoding, processing, decompression, and encoding all hop to the cooperative pool; the pipeline never blocks its own coordination on a Core Graphics call. Data loading doesn't run on it either – it's `URLSession` I/O.

The practical consequence: a custom ``ImageProcessing/process(_:context:)`` is called off the actor and off the main thread, and it can take as long as it needs without stalling other requests. A delegate method marked `@ImagePipelineActor`, on the other hand, is on the pipeline's critical path – keep it short.

## The Task Queues

Each stage has a ``TaskQueue`` that limits how many units of work run concurrently. The queues are priority-aware: the highest-priority pending work is dequeued first, and changing an ``ImageTask/priority`` reorders the work that hasn't started.

| Queue | Default | What it limits |
|---|---|---|
| ``ImagePipeline/Configuration-swift.struct/dataLoadingQueue`` | 6 | Concurrent `URLSession` data tasks. |
| ``ImagePipeline/Configuration-swift.struct/imageDecodingQueue`` | 1 | Concurrent decodes. Decoding is memory-hungry, so it's serialized by default. |
| ``ImagePipeline/Configuration-swift.struct/imageProcessingQueue`` | 2 | Concurrent ``ImageProcessing`` runs. |
| ``ImagePipeline/Configuration-swift.struct/imageDecompressingQueue`` | 2 | Concurrent decompressions (bitmapping). |
| ``ImagePipeline/Configuration-swift.struct/imageEncodingQueue`` | 1 | Concurrent encodes when writing processed images to ``DataCache``. |

The defaults are deliberately below the core count. Saturating every core with image work is the fastest way to make scrolling stutter – the goal is to leave headroom for the rest of the app.

```swift
let pipeline = ImagePipeline {
    $0.imageProcessingQueue.maxConcurrentTaskCount = 4
}
```

``ImagePrefetcher`` has a queue of its own, limited to 2 concurrent requests by default, on top of the pipeline's.

> Important: ``ImagePipeline/Configuration-swift.struct`` is a struct, but ``TaskQueue`` is a class. Copying a configuration *shares* its queues rather than duplicating them, so mutating a queue on a copy also changes it for the pipeline the copy came from. Start from a fresh `Configuration()` to get your own queues.

## Delegate Isolation

``ImagePipeline/Delegate-swift.protocol`` declares where each method runs in its own signature, rather than describing it in prose.

| Isolation | Methods |
|---|---|
| `@ImagePipelineActor` | ``ImagePipeline/Delegate/willLoadData(for:urlRequest:pipeline:)``, ``ImagePipeline/Delegate/willCache(data:image:for:pipeline:)``, ``ImagePipeline/Delegate/imageTaskDidStart(_:pipeline:)``, ``ImagePipeline/Delegate/imageTask(_:didReceiveEvent:pipeline:)`` |
| `nonisolated` | Everything else: the factories, ``ImagePipeline/Delegate/cacheKey(for:pipeline:)``, the policies, ``ImagePipeline/Delegate/decompress(response:request:pipeline:)``, and ``ImagePipeline/Delegate/imageTaskCreated(_:pipeline:)`` |

The split follows the question each method answers. The `nonisolated` ones *return a customization* – a decoder, a cache key, a policy – and the pipeline needs the answer wherever it happens to be, including from the synchronous ``ImagePipeline/Cache-swift.struct`` API. The isolated ones *report* something, so a delegate can accumulate state on the actor without a lock.

``ImagePipeline/Delegate/imageTaskCreated(_:pipeline:)`` is the exception among the reporting methods: it's `nonisolated` and called immediately, in whatever context created the task, so that you can see a task before it's scheduled.

A plain, non-isolated method still satisfies an isolated requirement, so most delegates need no annotations at all. Only a *conflicting* isolation is rejected – and a `@MainActor` delegate, which couldn't conform at all before Nuke 14, now works.

```swift
@MainActor
final class PipelineObserver: ImagePipeline.Delegate {
    var inFlight = 0

    nonisolated func imageTaskCreated(_ task: ImageTask, pipeline: ImagePipeline) {
        Task { @MainActor in self.inFlight += 1 }
    }
}
```

## Topics

### Concurrency

- ``ImagePipelineActor``
- ``TaskQueue``
