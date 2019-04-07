// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Nuke

class LinkedListTests: XCTestCase {
    let list = LinkedList<Int>()

    func testEmptyWhenCreated() {
        XCTAssertNil(list.first)
        XCTAssertNil(list.last)
        XCTAssertTrue(list.isEmpty)
    }

    // MARK: - Append

    func testAppendOnce() {
        // When
        list.append(1)

        // Then
        XCTAssertFalse(list.isEmpty)
        XCTAssertEqual(list.first?.value, 1)
        XCTAssertEqual(list.last?.value, 1)
    }

    func testAppendTwice() {
        // When
        list.append(1)
        list.append(2)

        // Then
        XCTAssertEqual(list.first?.value, 1)
        XCTAssertEqual(list.last?.value, 2)
    }

    // MARK: - Remove

    func testRemoveSingle() {
        // Given
        let node = list.append(1)

        // When
        list.remove(node)

        // Then
        XCTAssertNil(list.first)
        XCTAssertNil(list.last)
    }

    func testRemoveFromBeggining() {
        // Given
        let node = list.append(1)
        list.append(2)
        list.append(3)

        // When
        list.remove(node)

        // Then
        XCTAssertEqual(list.first?.value, 2)
        XCTAssertEqual(list.last?.value, 3)
    }

    func testRemoveFromEnd() {
        // Given
        list.append(1)
        list.append(2)
        let node = list.append(3)

        // When
        list.remove(node)

        // Then
        XCTAssertEqual(list.first?.value, 1)
        XCTAssertEqual(list.last?.value, 2)
    }

    func testRemoveFromMiddle() {
        // Given
        list.append(1)
        let node = list.append(2)
        list.append(3)

        // When
        list.remove(node)

        // Then
        XCTAssertEqual(list.first?.value, 1)
        XCTAssertEqual(list.last?.value, 3)
    }

    func testRemoveAll() {
        // Given
        list.append(1)
        list.append(2)
        list.append(3)

        // When
        list.removeAll()

        // Then
        XCTAssertNil(list.first)
        XCTAssertNil(list.last)
    }
}
