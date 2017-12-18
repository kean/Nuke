// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke


class BagTests: XCTestCase {
    var bag = Bag<Int>()

    func testInsert() {
        XCTAssertEqual(Set(bag), [])

        bag.insert(1)
        XCTAssertEqual(Set(bag), [1])

        bag.insert(2)
        XCTAssertEqual(Set(bag), [1, 2])
    }
}
