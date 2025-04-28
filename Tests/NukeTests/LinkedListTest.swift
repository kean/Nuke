// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation

@testable import Nuke

@Suite struct LinkedListTests {
    let list = LinkedList<Int>()

    @Test func emptyWhenCreated() {
        #expect(list.first == nil)
        #expect(list.last == nil)
        #expect(list.isEmpty)
    }

    // MARK: - Append

    @Test func appendOnce() {
        // When
        list.append(1)

        // Then
        #expect(list.isEmpty == false)
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 1)
        #expect(list.count == 1)
    }

    @Test func appendTwice() {
        // When
        list.append(1)
        list.append(2)

        // Then
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 2)
        #expect(list.count == 2)
    }

    // MARK: - Remove

    @Test func removeSingle() {
        // Given
        let node = list.append(1)

        // When
        list.remove(node)

        // Then
        #expect(list.first == nil)
        #expect(list.last == nil)
        #expect(list.count == 0)
    }

    @Test func removeFromBeggining() {
        // Given
        let node = list.append(1)
        list.append(2)
        list.append(3)

        // When
        list.remove(node)

        // Then
        #expect(list.first?.value == 2)
        #expect(list.last?.value == 3)
        #expect(list.count == 2)
    }

    @Test func removeFromEnd() {
        // Given
        list.append(1)
        list.append(2)
        let node = list.append(3)

        // When
        list.remove(node)

        // Then
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 2)
        #expect(list.count == 2)
    }

    @Test func removeFromMiddle() {
        // Given
        list.append(1)
        let node = list.append(2)
        list.append(3)

        // When
        list.remove(node)

        // Then
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 3)
        #expect(list.count == 2)
    }

    @Test func removeAll() {
        // Given
        list.append(1)
        list.append(2)
        list.append(3)

        // When
        list.removeAllElements()

        // Then
        #expect(list.first == nil)
        #expect(list.last == nil)
        #expect(list.count == 0)
    }
}
