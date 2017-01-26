// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

class ManagerPerformanceTests: XCTestCase {
    func testDefaultManager() {
        let view = ImageView()

        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(5000))")! }
        
        measure {
            for url in urls {
                Nuke.loadImage(with: url, into: view)
            }
        }
    }

    func testWithoutMemoryCache() {
        let loader = Loader(loader: DataLoader())
        let manager = Manager(loader: Deduplicator(loader: loader))
        
        let view = ImageView()
        
        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(5000))")! }
        
        measure {
            for url in urls {
                manager.loadImage(with: url, into: view)
            }
        }
    }
    
    func testWithoutDeduplicator() {
        let loader = Loader(loader: DataLoader())
        let manager = Manager(loader: loader)

        let view = ImageView()

        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(5000))")! }
        
        measure {
            for url in urls {
                manager.loadImage(with: url, into: view)
            }
        }
    }
}

class CachePerformanceTests: XCTestCase {
    func testCacheWrite() {
        let cache = Cache()
        let image = Image()
        
        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(500))")! }
        
        measure {
            for url in urls {
                let request = Request(url: url)
                cache[request] = image
            }
        }
    }
    
    func testCacheHit() {
        let cache = Cache()
        
        for i in 0..<200 {
            cache[Request(url: URL(string: "http://test.com/\(i))")!)] = Image()
        }
        
        var hits = 0
        
        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(200))")! }
        
        measure {
            for url in urls {
                let request = Request(url: url)
                if cache[request] != nil {
                    hits += 1
                }
            }
        }
        
        print("hits: \(hits)")
    }
    
    func testCacheMiss() {
        let cache = Cache()
        
        var misses = 0
        
        let urls = (0..<10_000).map { _ in return URL(string: "http://test.com/\(rnd(200))")! }
        
        measure {
            for url in urls {
                let request = Request(url: url)
                if cache[request] == nil {
                    misses += 1
                }
            }
        }
        
        print("misses: \(misses)")
    }
}

class DeduplicatorPerformanceTests: XCTestCase {
    func testDeduplicatorHits() {
        let deduplicator = Deduplicator(loader: MockImageLoader())
        
        let request = Request(url: URL(string: "http://test.com/\(arc4random())")!)
        
        measure {
            let cts = CancellationTokenSource()
            for _ in (0..<10_000) {
                deduplicator.loadImage(with: request, token:cts.token) { _ in return }
            }
        }
    }
 
    func testDeduplicatorMisses() {
        let deduplicator = Deduplicator(loader: MockImageLoader())
        
        let requests = (0..<10_000)
            .map { _ in return URL(string: "http://test.com/\(arc4random())")! }
            .map { return Request(url: $0) }
        
        measure {
            let cts = CancellationTokenSource()
            for request in requests {
                deduplicator.loadImage(with: request, token:cts.token) { _ in return }
            }
        }
    }
}

class MockImageLoader: Loading {
    func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        return
    }
}
