// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

// BUG (docs vs behavior): an `ImagePipeline.Error` thrown from
// `ImagePipeline.Delegate.willLoadData(for:urlRequest:pipeline:)` isn't
// wrapped in `.dataLoadingFailed`, so the request fails with an error that the
// pipeline never produced for it – for example `.dataMissingInCache` for a
// request that doesn't even use `.returnCacheDataDontLoad`.
//
// The contract, Sources/Nuke/Pipeline/ImagePipeline+Delegate.swift:
//
//     /// - throws: If an error is thrown, the image request fails with
//     ///   ``ImagePipeline/Error/dataLoadingFailed(error:)`` wrapping the error.
//
// and Documentation/Nuke.docc/Customization/LoadingData/loading-data.md:
// "Throwing an error cancels the request and surfaces the error as
// ``ImagePipeline/Error/dataLoadingFailed(error:)``."
//
// Sources/Nuke/Tasks/TaskFetchOriginalData.swift `performDataLoad` shares one
// `catch` between the delegate and the download, and passes every
// `ImagePipeline.Error` through as is (it exists for the
// `.dataDownloadExceededMaximumSize` that the download throws). A custom
// `data` closure that throws the same error *is* wrapped
// (`performAsyncDataLoad`), so the two paths disagree too.
//
// Expected: `.dataLoadingFailed(error: ImagePipeline.Error.dataMissingInCache)`.
// Actual:   `.dataMissingInCache`.

@Suite(.timeLimit(.minutes(5)))
struct WillLoadDataPipelineErrorNotWrappedBugTests {
    @Test func pipelineErrorThrownFromWillLoadDataIsWrapped() async throws {
        // GIVEN a delegate that rejects the request with a pipeline error
        let pipeline = ImagePipeline(delegate: _RejectingDelegate()) {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }

        // WHEN
        do {
            _ = try await pipeline.data(for: Test.request)
            Issue.record("Expected the request to fail")
        } catch {
            // THEN
            guard case .dataLoadingFailed(let underlying) = error else {
                Issue.record("Expected dataLoadingFailed, got \(error)")
                return
            }
            #expect((underlying as? ImagePipeline.Error) == .dataMissingInCache)
        }
    }

    /// The same error thrown from a custom data closure is wrapped.
    @Test func pipelineErrorThrownFromDataClosureIsWrapped() async throws {
        let pipeline = ImagePipeline {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }
        let request = ImageRequest(id: "a", data: { throw ImagePipeline.Error.dataMissingInCache })
        do {
            _ = try await pipeline.data(for: request)
            Issue.record("Expected the request to fail")
        } catch {
            guard case .dataLoadingFailed = error else {
                Issue.record("Expected dataLoadingFailed, got \(error)")
                return
            }
        }
    }
}

private final class _RejectingDelegate: ImagePipeline.Delegate, @unchecked Sendable {
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        throw ImagePipeline.Error.dataMissingInCache
    }
}
