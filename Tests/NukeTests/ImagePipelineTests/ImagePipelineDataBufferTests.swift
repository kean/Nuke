// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImagePipelineDataBufferTests {
    @Test(arguments: [12288, -1])
    func reportsLogicalBytesWithoutChangingTheBody(expectedLength: Int) async throws {
        let body = Data(repeating: 7, count: 12288)
        let loader = MockDataLoader()
        loader.results[Test.url] = .success((body, URLResponse(url: Test.url, mimeType: "image/jpeg", expectedContentLength: expectedLength, textEncodingName: nil)))
        let delegate = await BufferDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = loader
            $0.imageCache = nil
        }

        let (data, _) = try await pipeline.data(for: Test.request)

        #expect(data == body)
        let updates = await delegate.updates
        #expect(updates.count == (expectedLength > 0 ? 2 : 1))
        if expectedLength > 0 {
            let reservation = try #require(updates.first)
            #expect(reservation.operation == .initialReservation)
            #expect(reservation.bufferedByteCount == 6144)
            #expect(reservation.incomingByteCount == 0)
            #expect(reservation.requestedCapacity == expectedLength)
        }
        let append = try #require(updates.last)
        #expect(append.operation == .append)
        #expect(append.bufferedByteCount == 6144)
        #expect(append.incomingByteCount == 6144)
        #expect(append.requestedCapacity == nil)
        #expect(append.response.expectedContentLength == Int64(expectedLength))
        #expect(append.response.mimeType == "image/jpeg")
    }

    @Test func singleChunkDoesNotReportAnAllocation() async throws {
        let delegate = await BufferDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = MockDataLoader()
            $0.imageCache = nil
        }

        let (data, _) = try await pipeline.data(for: Test.request)

        #expect(data == Test.data)
        #expect(await delegate.updates.isEmpty)
    }

    @Test func sizeRejectionPrecedesTheReservationHook() async throws {
        let loader = MockDataLoader()
        loader.results[Test.url] = .success((Test.data, URLResponse(url: Test.url, mimeType: nil, expectedContentLength: Test.data.count, textEncodingName: nil)))
        let delegate = await BufferDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = loader
            $0.imageCache = nil
            $0.maximumResponseDataSize = 100
        }

        await #expect(throws: ImagePipeline.Error.dataDownloadExceededMaximumSize) {
            try await pipeline.data(for: Test.request)
        }
        #expect(await delegate.updates.isEmpty)
    }

    @Test func resumedReservationIncludesThePrefix() async throws {
        let server = MockRangeServer(data: Test.data, validator: ["ETag": "\"v1\""])
        server.steps = [.fail(after: 10000), .serve]
        let delegate = await BufferDelegate()
        let pipeline = ImagePipeline(delegate: delegate) {
            $0.dataLoader = server
            $0.imageCache = nil
        }
        _ = try? await pipeline.data(for: Test.request)
        await delegate.reset()

        let (data, _) = try await pipeline.data(for: Test.request)

        #expect(data == Test.data)
        #expect(server.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=10000-")
        let updates = await delegate.updates
        let reservation = try #require(updates.first)
        #expect(reservation.operation == .resumedReservation)
        #expect(reservation.bufferedByteCount == 10000)
        #expect(reservation.incomingByteCount == 0)
        #expect(reservation.requestedCapacity == Test.data.count)
        #expect(reservation.response.expectedContentLength == Int64(Test.data.count - 10000))
        #expect(updates.dropFirst().allSatisfy { $0.operation == .append && $0.requestedCapacity == nil })
    }

    @Test func defaultDelegateStillReturnsTheCompleteBody() async throws {
        let loader = MockDataLoader()
        loader.results[Test.url] = .success((Test.data, URLResponse(url: Test.url, mimeType: nil, expectedContentLength: Test.data.count, textEncodingName: nil)))
        let pipeline = ImagePipeline {
            $0.dataLoader = loader
            $0.imageCache = nil
        }

        let (data, _) = try await pipeline.data(for: Test.request)

        #expect(data == Test.data)
    }
}

@ImagePipelineActor
private final class BufferDelegate: ImagePipeline.Delegate {
    var updates: [ImagePipeline.DataBufferUpdateContext] = []

    func willUpdateDataBuffer(for request: ImageRequest, context: ImagePipeline.DataBufferUpdateContext, pipeline: ImagePipeline) {
        updates.append(context)
    }

    func reset() {
        updates.removeAll()
    }
}
