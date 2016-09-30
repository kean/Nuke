// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

class ManagerPerformanceTests: XCTestCase {
    func testSharedManagerPerfomance() {
        let view = ImageView()
        
        measure {
            for _ in 0..<10_000 {
                // There are going to be some cache hits and cache misses
                let url = URL(string: "http://test.com/\(arc4random_uniform(5000))")!
                Nuke.loadImage(with: url, into: view)
            }
        }
    }

    func testPerformanceWithoutMemoryCache() {
        let loader = Loader(loader: DataLoader(), decoder: DataDecoder(), cache: nil)
        let manager = Manager(loader: Deduplicator(loader: loader))
        
        let view = ImageView()
        
        measure {
            for _ in 0..<10_000 {
                let url = URL(string: "http://test.com/\(arc4random_uniform(5000))")!
                manager.loadImage(with: url, into: view)
            }
        }
    }
    
    func testPerformanceWithoutDeduplicator() {
        let loader = Loader(loader: DataLoader(), decoder: DataDecoder(), cache: nil)
        let manager = Manager(loader: loader)

        let view = ImageView()

        measure {
            for _ in 0..<10_000 {
                let url = URL(string: "http://test.com/\(arc4random_uniform(5000))")!
                manager.loadImage(with: url, into: view)
            }
        }
    }
}

class CachePerformanceTests: XCTestCase {
    func testCacheWritePerformance() {
        let cache = Cache()
        let image = UIImage()
        
        measure {
            for _ in 0..<10_000 {
                let url = URL(string: "http://test.com/\(arc4random_uniform(200))")!
                let request = Request(url: url)
                cache[request] = image
            }
        }
    }
    
    func testCacheHitPerformance() {
        let cache = Cache()
        
        for i in 0..<200 {
            cache[Request(url: URL(string: "http://test.com/\(i))")!)] = UIImage()
        }
        
        var hits = 0
        
        measure {
            for _ in 0..<10_000 {
                let url = URL(string: "http://test.com/\(arc4random_uniform(200))")!
                let request = Request(url: url)
                if cache[request] != nil {
                    hits += 1
                }
            }
        }
        
        print("hits: \(hits)")
    }
    
    func testCacheMissPerformance() {
        let cache = Cache()
        
        var misses = 0
        
        measure {
            for _ in 0..<10_000 {
                let url = URL(string: "http://test.com/\(arc4random_uniform(200))")!
                let request = Request(url: url)
                if cache[request] == nil {
                    misses += 1
                }
            }
        }
        
        print("misses: \(misses)")
    }
}
