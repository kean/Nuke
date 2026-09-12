// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

// The decorators the probe hands the pipeline in place of what its delegate
// returned. Each one forwards every call unchanged and counts on the way
// through; none of them changes an argument, a result, or when a callback is
// called.

extension DemoPipelineProbe {
    /// Listens to a `DataLoader`'s session, as its `delegate`.
    ///
    /// A `DataLoader` isn't wrapped: the pipeline casts the loader to ask it
    /// for the metrics `URLSession` collected, which is also how its
    /// diagnostics know that `URLCache` answered. It forwards the session's
    /// events to its delegate instead. Only the events that don't ask the
    /// delegate for a decision are implemented here, so the loader keeps
    /// handling redirects, challenges, and caching on its own.
    final class SessionObserver: NSObject, URLSessionDataDelegate, Sendable {
        private let counters: Counters

        init(counters: Counters) {
            self.counters = counters
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            counters.loadStarted(.sessionTask(ObjectIdentifier(task)))
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            counters.load(.sessionTask(ObjectIdentifier(dataTask)), didReceive: data.count)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            guard let transaction = metrics.transactionMetrics.last else { return }
            counters.load(
                .sessionTask(ObjectIdentifier(task)),
                isServedFromHTTPCache: transaction.resourceFetchType == .localCache,
                isReusedConnection: transaction.isReusedConnection
            )
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            // `DataLoader` rejects a status code outside 200..<300 by cancelling
            // the task, so a cancellation with such a response is a failure.
            let isAcceptable = (task.response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? true
            let outcome: Counters.LoadOutcome = switch error {
            case nil: isAcceptable ? .completed : .failed
            case let error as URLError where error.code == .cancelled: isAcceptable ? .cancelled : .failed
            default: .failed
            }
            counters.loadCompleted(.sessionTask(ObjectIdentifier(task)), outcome: outcome)
        }
    }

    /// Wraps a loader other than `DataLoader`.
    ///
    /// It calls `didReceiveData` and `completion` exactly when, and as often
    /// as, the loader does, and passes a cancel straight on. A load stays in
    /// flight until its `completion`, even after a cancel, because that is
    /// when the pipeline frees the data loading slot.
    final class CountingDataLoader: DataLoading {
        let base: any DataLoading
        private let counters: Counters

        init(_ base: any DataLoading, counters: Counters) {
            self.base = base
            self.counters = counters
        }

        func loadData(
            with request: URLRequest,
            didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
            completion: @escaping @Sendable (Error?) -> Void
        ) -> any Cancellable {
            let counters = counters
            let id = counters.loadStarted()
            let cancellable = base.loadData(with: request, didReceiveData: { data, response in
                counters.load(id, didReceive: data.count)
                didReceiveData(data, response)
            }, completion: { error in
                counters.loadCompleted(id, outcome: error == nil ? .completed : .failed)
                completion(error)
            })
            return CountingCancellable(base: cancellable, id: id, counters: counters)
        }
    }

    private struct CountingCancellable: Cancellable {
        let base: any Cancellable
        let id: Counters.LoadID
        let counters: Counters

        func cancel() {
            // Counted first: a loader may call `completion` from inside `cancel`.
            counters.loadCancelled(id)
            base.cancel()
        }
    }

    /// Times a decoder.
    ///
    /// The pipeline asks the delegate for a decoder once per download and keeps
    /// it for every chunk, so each wrapper wraps the one decoder it was created
    /// with – `ImageDecoders.Default` keeps the state of an incremental decode.
    final class CountingDecoder: ImageDecoding, CustomStringConvertible {
        let base: any ImageDecoding
        private let counters: Counters

        init(_ base: any ImageDecoding, counters: Counters) {
            self.base = base
            self.counters = counters
        }

        /// Forwarded, so the decode runs where the decoder asked for.
        var isAsynchronous: Bool {
            base.isAsynchronous
        }

        func decode(_ data: Data) throws -> ImageContainer {
            let isAsynchronous = base.isAsynchronous
            counters.decodeStarted(isAsynchronous: isAsynchronous)
            let startedAt = ContinuousClock.now
            do {
                let container = try base.decode(data)
                counters.decodeFinished(isAsynchronous: isAsynchronous, startedAt: startedAt, result: .image(format: container.type.demoFormatName, isPreview: false))
                return container
            } catch {
                counters.decodeFinished(isAsynchronous: isAsynchronous, startedAt: startedAt, result: .failed)
                throw error
            }
        }

        func decodePartiallyDownloadedData(_ data: Data) -> ImageContainer? {
            let isAsynchronous = base.isAsynchronous
            counters.decodeStarted(isAsynchronous: isAsynchronous)
            let startedAt = ContinuousClock.now
            let preview = base.decodePartiallyDownloadedData(data)
            let result: Counters.DecodeResult = preview.map { .image(format: $0.type.demoFormatName, isPreview: true) } ?? .noPreview
            counters.decodeFinished(isAsynchronous: isAsynchronous, startedAt: startedAt, result: result)
            return preview
        }

        /// The decoder's own, which is what `ImagePipeline.Error` prints when a
        /// decode fails.
        var description: String {
            String(describing: base)
        }
    }

    /// Times an encoder.
    final class CountingEncoder: ImageEncoding {
        let base: any ImageEncoding
        private let counters: Counters

        init(_ base: any ImageEncoding, counters: Counters) {
            self.base = base
            self.counters = counters
        }

        func encode(_ image: PlatformImage) -> Data? {
            measure { base.encode(image) }
        }

        /// Forwarded to the encoder's own, which for a GIF returns the original
        /// data rather than encoding the image.
        func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data? {
            measure { base.encode(container, context: context) }
        }

        private func measure(_ encode: () -> Data?) -> Data? {
            counters.encodeStarted()
            let startedAt = ContinuousClock.now
            defer { counters.encodeFinished(startedAt: startedAt) }
            return encode()
        }
    }

    /// Counts the reads of a memory cache.
    ///
    /// The pipeline asks the delegate for the memory cache on every read and
    /// write, including NukeUI's synchronous lookups on the main thread, so the
    /// probe keeps one of these for the pipeline's cache rather than creating
    /// one per lookup.
    final class CountingImageCache: ImageCaching {
        let base: any ImageCaching
        private let counters: Counters

        init(_ base: any ImageCaching, counters: Counters) {
            self.base = base
            self.counters = counters
        }

        subscript(key: ImageCacheKey) -> ImageContainer? {
            get {
                let container = base[key]
                counters.memoryCacheLookup(isHit: container.map { !$0.isPreview } ?? false, isOnMainThread: Thread.isMainThread)
                return container
            }
            set {
                base[key] = newValue
            }
        }

        func removeAll() {
            base.removeAll()
        }
    }

    /// Counts the reads of a disk cache.
    struct CountingDataCache: DataCaching {
        let base: any DataCaching
        let counters: Counters

        func cachedData(for key: String) -> Data? {
            let data = base.cachedData(for: key)
            counters.diskCacheLookup(byteCount: data?.count)
            return data
        }

        func containsData(for key: String) -> Bool {
            base.containsData(for: key)
        }

        func storeData(_ data: Data, for key: String) {
            base.storeData(data, for: key)
        }

        func removeData(for key: String) {
            base.removeData(for: key)
        }

        func removeAll() {
            base.removeAll()
        }
    }
}

extension Optional<AssetType> {
    /// The short name the pipeline's diagnostics use for a format, such as
    /// `"jpeg"`, so the figures read the same with them on or off.
    fileprivate var demoFormatName: String {
        switch self {
        case .jpeg?: "jpeg"
        case .png?: "png"
        case .gif?: "gif"
        case .heic?: "heic"
        case .webp?: "webp"
        case .avif?: "avif"
        case .bmp?: "bmp"
        case .tiff?: "tiff"
        case .ico?: "ico"
        case .jpeg2000?: "jpeg2000"
        case .jxl?: "jxl"
        case .mp4?: "mp4"
        case .m4v?: "m4v"
        case .mov?: "mov"
        case let type?: type.rawValue
        case nil: "unknown"
        }
    }
}
