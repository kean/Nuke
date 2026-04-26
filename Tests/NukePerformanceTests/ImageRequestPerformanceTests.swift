// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import Nuke

@Suite(.serialized)
@MainActor
struct ImageRequestPerformanceTests {
    @Test
    func storingRequestInCollections() {
        let urls = (0..<200_000).map { _ in URL(string: "http://test.com/\(Int.random(in: 0..<200))")! }
        let requests = urls.map { ImageRequest(url: $0) }

        measure {
            var array = [ImageRequest]()
            for request in requests {
                array.append(request)
            }
        }
    }

    @Test
    func creatingRequests() {
        let urls = (0..<200_000).map { _ in URL(string: "http://test.com/\(Int.random(in: 0..<200))")! }

        measure {
            var requests = [ImageRequest]()
            requests.reserveCapacity(urls.count)
            for url in urls {
                requests.append(ImageRequest(url: url))
            }
        }
    }

    @Test
    func creatingRequestsWithOptions() {
        let processor = MockImageProcessor(id: "p1")
        let urls = (0..<100_000).map { _ in URL(string: "http://test.com/\(Int.random(in: 0..<200))")! }

        measure {
            var requests = [ImageRequest]()
            requests.reserveCapacity(urls.count)
            for url in urls {
                requests.append(ImageRequest(
                    url: url,
                    processors: [processor],
                    priority: .high,
                    options: [.reloadIgnoringCachedData]
                ))
            }
        }
    }

    /// Exercises the CoW copy path: the source request is shared with an outer
    /// scope, so each mutation triggers a `Container` copy.
    @Test
    func mutatingSharedRequest() {
        let request = ImageRequest(url: URL(string: "http://test.com/example")!)

        measure {
            for _ in 0..<1_000_000 {
                var copy = request
                copy.priority = .high
            }
        }
    }

    /// Exercises the CoW fast path: the request is uniquely owned, so the
    /// `isKnownUniquelyReferenced` check short-circuits the copy.
    @Test
    func mutatingUniqueRequest() {
        var request = ImageRequest(url: URL(string: "http://test.com/example")!)

        measure {
            for i in 0..<10_000_000 {
                request.priority = (i & 1) == 0 ? .high : .normal
            }
        }
    }

    @Test
    func accessingImageID() {
        let urls = (0..<200_000).map { _ in URL(string: "http://test.com/\(Int.random(in: 0..<200))")! }
        let requests = urls.map { ImageRequest(url: $0) }

        var nonNil = 0
        measure {
            for request in requests {
                if request.imageID != nil {
                    nonNil += 1
                }
            }
        }

        print("nonNil: \(nonNil)")
    }
}
