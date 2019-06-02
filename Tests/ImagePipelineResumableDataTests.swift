// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ImagePipelineResumableDataTests: XCTestCase {
    private var dataLoader: _MockResumableDataLoader!
    private var pipeline: ImagePipeline!

    override func setUp() {
        dataLoader = _MockResumableDataLoader()
        ResumableData.cache.removeAll()
        pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
    }

    func testThatProgressIsReported() {
        // Given an initial request failed mid download

        // Expect the progress for the first part of the download to be reported.
        let expectedProgressInitial = expectProgress(
            [(3799, 22789), (7598, 22789), (11397, 22789)]
        )
        expect(pipeline).toFailRequest(Test.request, progress: { _, completed, total in
            expectedProgressInitial.received((completed, total))
        })
        wait()

        // Expect progress closure to continue reporting the progress of the
        // entire download
        let expectedProgersRemaining = expectProgress(
            [(15196, 22789), (18995, 22789), (22789, 22789)]
        )
        expect(pipeline).toLoadImage(with: Test.request, progress: { _, completed, total in
            expectedProgersRemaining.received((completed, total))
        })
        wait()
    }
}

private class _MockResumableDataLoader: DataLoading {
    private let queue = DispatchQueue(label: "_MockResumableDataLoader")

    let data: Data = Test.data(name: "fixture", extension: "jpeg")
    let eTag: String = "img_01"

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        let headers = request.allHTTPHeaderFields

        func sendChunks(_ chunks: [Data], of data: Data, statusCode: Int) {
            func sendChunk(_ chunk: Data) {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: "HTTP/1.2",
                    headerFields: [
                        "Accept-Ranges": "bytes",
                        "ETag": eTag,
                        "Content-Range": "bytes \(chunk.startIndex)-\(chunk.endIndex)/\(data.count)",
                        "Content-Length": "\(data.count)"
                    ]
                )!

                didReceiveData(chunk, response)
            }

            var chunks = chunks
            while let chunk = chunks.first {
                chunks.removeFirst()
                queue.async {
                    sendChunk(chunk)
                }
            }
        }


        // Check if the client already has some resumable data available.
        if let range = headers?["Range"], let validator = headers?["If-Range"] {
            let offset = _groups(regex: "bytes=(\\d*)-", in: range)[0]
            XCTAssertNotNil(offset)

            XCTAssertEqual(validator, eTag, "Expected validator to be equal to ETag")
            guard validator == eTag else { // Expected ETag
                return _Task()
            }

            // Send remaining data in chunks
            let remainingData = data[Int(offset)!...]
            let chunks = Array(_createChunks(for: remainingData, size: data.count / 6 + 1))

            sendChunks(chunks, of: remainingData, statusCode: 206)
            queue.async {
                completion(nil)
            }
        } else {
            // Send half of chunks.
            var chunks = Array(_createChunks(for: data, size: data.count / 6 + 1))
            chunks.removeLast(chunks.count / 2)

            sendChunks(chunks, of: data, statusCode: 200)
            queue.async {
                completion(NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue, userInfo: [:]))
            }
        }

        return _Task()
    }

    private class _Task: Cancellable {
        func cancel() { }
    }
}
