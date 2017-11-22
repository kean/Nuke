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
                Manager.shared.loadImage(with: url, into: view)
            }
        }
    }

    func testWithoutMemoryCache() {
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


class MockImageLoader: Loading {
    func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        return
    }
}
