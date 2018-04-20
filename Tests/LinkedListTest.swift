// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class LinkedListTests: XCTestCase {
    let list = LinkedList<Int>()

    // MARK: `append(_:)`

    func testAppend() {
        XCTAssertNil(list.first)
        XCTAssertNil(list.last)
        XCTAssertTrue(list.isEmpty)

        list.append(1)
        XCTAssertFalse(list.isEmpty)
        XCTAssertEqual(list.first?.value, 1)
        XCTAssertEqual(list.last?.value, 1)

        list.append(2)
        XCTAssertEqual(list.first?.value, 1)
        XCTAssertEqual(list.last?.value, 2)
    }

    // MARK: `remove(_:)`

    func testRemoveSingle() {
        let node = list.append(1)

        list.remove(node)
        XCTAssertNil(list.first)
        XCTAssertNil(list.last)
    }

    func testRemoveFromBeggining() {
        let node = list.append(1)
        list.append(2)
        list.append(3)

        list.remove(node)
        XCTAssertEqual(list.first?.value, 2)
        XCTAssertEqual(list.last?.value, 3)
    }

    func testRemoveFromEnd() {
        list.append(1)
        list.append(2)
        let node = list.append(3)

        list.remove(node)
        XCTAssertEqual(list.first?.value, 1)
        XCTAssertEqual(list.last?.value, 2)
    }

    func testRemoveFromMiddle() {
        list.append(1)
        let node = list.append(2)
        list.append(3)

        list.remove(node)
        XCTAssertEqual(list.first?.value, 1)
        XCTAssertEqual(list.last?.value, 3)
    }

    func testRemoveAll() {
        list.append(1)
        list.append(2)
        list.append(3)

        list.removeAll()
        XCTAssertNil(list.first)
        XCTAssertNil(list.last)
    }
}
