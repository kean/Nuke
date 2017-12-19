// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke


class BagTests: XCTestCase {
    var bag = Bag<Int>()

    // MARK: `insert(_:)`

    func testInsert() {
        XCTAssertEqual(Set(bag), [])

        bag.insert(1)
        XCTAssertEqual(Set(bag), [1])

        bag.insert(2)
        XCTAssertEqual(Set(bag), [1, 2])
        
        bag.insert(3)
        XCTAssertEqual(Set(bag), [1, 2, 3])
        
        bag.insert(4)
        XCTAssertEqual(Set(bag), [1, 2, 3, 4])
    }
}
