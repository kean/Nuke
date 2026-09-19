// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension DemoPipelineProbe {
    /// A call the pipeline made to its delegate, and what the delegate
    /// answered, for a screen that lists them.
    ///
    /// A probe reports events only to the handler it was created with (see
    /// ``DemoPipelineProbe/makePipeline(_:configuration:delegate:onEvent:)``);
    /// without one, a hook costs a check for `nil`. Only the calls the Pipeline
    /// Delegate screen lists are reported: add a case when a screen needs
    /// another.
    struct Event: Sendable {
        /// The request the pipeline asked about.
        let request: ImageRequest
        let kind: Kind

        enum Kind: Sendable {
            /// `cacheKey(for:pipeline:)`, with the key the delegate returned:
            /// `nil` for the default one. The pipeline asks on every read and
            /// write of either cache, including NukeUI's lookups on the main
            /// thread.
            case cacheKey(String?)
            /// `willLoadData(for:urlRequest:pipeline:)`, with the URL request
            /// the delegate returned. Not reported if the delegate threw.
            case willLoadData(URLRequest)
            /// `willCache(data:image:for:pipeline:)`: the size of the data the
            /// pipeline is about to write to the disk cache, whether it is an
            /// encoded image rather than the original data, and the size of
            /// the data the delegate returned – `nil` if it returned `nil` or
            /// nothing, which leaves the cache untouched.
            case willCache(byteCount: Int, isEncodedImage: Bool, storedByteCount: Int?)
            /// `imageTaskDidStart(_:pipeline:)`.
            case imageTaskDidStart
            /// The last `.progress` event of a task: the one that completes its
            /// data, when the size is known. The ones before it aren't
            /// reported, which keeps the handler off the path every chunk of
            /// data takes.
            case progress(ImageTask.Progress)
            /// A `.preview` event.
            case preview
            /// The `.finished` event.
            case finished(Result<ImageResponse, ImagePipeline.Error>)
        }
    }

    /// Called with every ``Event`` of a probe, on the thread the pipeline
    /// called the delegate on – often the pipeline's actor, sometimes the main
    /// thread – while the pipeline waits. Hand the event off and return.
    typealias EventHandler = @Sendable (Event) -> Void

    /// A call between the pipeline and its data loader, for a screen that
    /// lists them.
    ///
    /// Reported by ``CountingDataLoader``, so only for the loads it wraps:
    /// those of every loader but a `DataLoader`. The calls are the ones the
    /// pipeline made and received, after the probe's routing: for a fixture
    /// URL, the fixture loader's.
    struct LoadEvent: Sendable {
        /// The request the pipeline is loading the data for.
        let request: ImageRequest
        let kind: Kind

        enum Kind: Sendable {
            /// The pipeline called `loadData(with:didReceiveData:completion:)`
            /// on `loader` with this URL request.
            case started(URLRequest, loader: any DataLoading)
            /// The loader called `didReceiveData`: once per chunk.
            case received(byteCount: Int, response: URLResponse)
            /// The pipeline cancelled the load.
            case cancelled
            /// The loader called `completion`.
            case completed((any Error)?)
        }
    }

    /// Called with every ``LoadEvent`` of a probe, on the loader's thread and
    /// before the pipeline hears of the call. It is called for every chunk of
    /// data, so hand the event off and return.
    typealias LoadEventHandler = @Sendable (LoadEvent) -> Void
}
