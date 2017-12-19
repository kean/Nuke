// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class ManagerPerformanceTests: XCTestCase {
    func testDefaultManager() {
        let view = ImageView()

        let urls = (0..<25_000).map { _ in return URL(string: "http://test.com/\(rnd(5000))")! }
        
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
            cache[Request(url: URL(string: "http://test.com/\(i)")!)] = Image()
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


class BagPerformanceTests: XCTestCase {
    func testTestInsertTwoInts() {
        measure {
            for _ in 0..<500_000 {
                var bag = Bag<Int>()
                bag.insert(1)
                bag.insert(2)
            }
        }
    }
    
    func testTestInsertThreeInts() {
        measure {
            for _ in 0..<500_000 {
                var bag = Bag<Int>()
                bag.insert(1)
                bag.insert(2)
                bag.insert(3)
            }
        }
    }
    
    func testInsertLotsOfInts() {
        measure {
            var bag = Bag<Int>()
            for _ in 0..<500_000 { // also makes sure that we don't stack overflow
                bag.insert(1)
            }
        }
    }
    
    func testTestInsertTwoClosures() {
        measure {
            for _ in 0..<500_000 {
                var bag = Bag<() -> Void>()
                bag.insert({ print(1) })
                bag.insert({ print(2) })
            }
        }
    }
    
    func testTestInsertThreeClosures() {
        measure {
            for _ in 0..<500_000 {
                var bag = Bag<() -> Void>()
                bag.insert({ print(1) })
                bag.insert({ print(2) })
                bag.insert({ print(3) })
            }
        }
    }
    
    func testInsertLotsOfClosures() {
        measure {
            var bag = Bag<() -> Void>()
            for _ in 0..<500_000 {
                bag.insert({ print(1) })
            }
        }
    }
}


class MockImageLoader: Loading {
    func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void) {
        return
    }
}
