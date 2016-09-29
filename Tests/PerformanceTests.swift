// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

class ManagerPerformanceTests: XCTestCase {
    func testPeformanceWithDeduplicator() {
        let loader = Loader(loader: DataLoader(), decoder: DataDecoder(), cache: nil)
        let manager = Manager(loader: Deduplicator(loader: loader))

        let view = ImageView()

        measure {
            for _ in 0..<10_000 {
                let url = URL(string: "http://test.com/\(arc4random_uniform(200))")!
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
                let url = URL(string: "http://test.com/\(arc4random_uniform(200))")!
                manager.loadImage(with: url, into: view)
            }
        }
    }
}
