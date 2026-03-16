// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite(.timeLimit(.minutes(2)))
struct LinkedListTests {
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
        #expect(!list.isEmpty)
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 1)
    }

    @Test func appendTwice() {
        // When
        list.append(1)
        list.append(2)

        // Then
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 2)
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
    }

    @Test func removeFromBeginning() {
        // Given
        let node = list.append(1)
        list.append(2)
        list.append(3)

        // When
        list.remove(node)

        // Then
        #expect(list.first?.value == 2)
        #expect(list.last?.value == 3)
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
    }

    // MARK: - Prepend

    @Test func prependToEmptyList() {
        // Given
        let node = LinkedList<Int>.Node(value: 42)

        // When
        list.prepend(node)

        // Then
        #expect(list.first?.value == 42)
        #expect(list.last?.value == 42)
        #expect(!list.isEmpty)
    }

    @Test func prependToNonEmptyList() {
        // Given
        list.append(2)
        list.append(3)
        let node = LinkedList<Int>.Node(value: 1)

        // When
        list.prepend(node)

        // Then
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 3)
    }

    // MARK: - Node Links

    @Test func appendPreservesOrder() {
        // Given
        list.append(1)
        list.append(2)
        list.append(3)

        // Then values are accessible in insertion order via first/last
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 3)
        #expect(!list.isEmpty)
    }
}
