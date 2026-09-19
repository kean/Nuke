// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
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

@Suite(.timeLimit(.minutes(5)))
struct LinkedListMoveToLastTests {
    let list = LinkedList<Int>()

    @Test func countIsZeroForAnEmptyList() {
        #expect(list.count == 0)
    }

    @Test func countReflectsTheNumberOfElements() {
        // When
        list.append(1)
        list.append(2)
        list.append(3)

        // Then
        #expect(list.count == 3)

        // When
        list.removeAllElements()

        // Then
        #expect(list.count == 0)
    }

    @Test func movingTheFirstNodeToLast() {
        // Given
        let node = list.append(1)
        list.append(2)
        list.append(3)

        // When
        list.moveToLast(node)

        // Then
        #expect(list.first?.value == 2)
        #expect(list.last?.value == 1)
        #expect(list.count == 3)
    }

    @Test func movingAMiddleNodeToLast() {
        // Given
        list.append(1)
        let node = list.append(2)
        list.append(3)

        // When
        list.moveToLast(node)

        // Then
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 2)
        #expect(list.count == 3)
        #expect(list.drained() == [1, 3, 2])
    }

    @Test func movingTheLastNodeToLastIsANoOp() {
        // Given
        list.append(1)
        list.append(2)
        let node = list.append(3)

        // When
        list.moveToLast(node)

        // Then
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 3)
        #expect(list.count == 3)
    }

    @Test func movingTheOnlyNodeToLastIsANoOp() {
        // Given
        let node = list.append(1)

        // When
        list.moveToLast(node)

        // Then
        #expect(list.first?.value == 1)
        #expect(list.last?.value == 1)
        #expect(list.count == 1)
    }

    @Test func movingEveryNodePreservesTheListIntegrity() {
        // Given
        for value in 1...4 { list.append(value) }

        // When each node is given a "second chance" in turn
        for _ in 1...4 {
            list.moveToLast(list.first!)
        }

        // Then the list is rotated back into its original order
        #expect(list.count == 4)
        #expect(list.drained() == [1, 2, 3, 4])
    }
}

private extension LinkedList {
    /// Removes and returns every element, front to back.
    ///
    /// Stops after `limit` elements, so a list with broken links fails the
    /// test instead of hanging it.
    func drained(limit: Int = 1_000) -> [Element] {
        var values: [Element] = []
        while let node = first, values.count < limit {
            values.append(node.value)
            remove(node)
        }
        return values
    }

    /// Removes and returns every element, back to front, following the
    /// `previous` links.
    ///
    /// Stops after `limit` elements, so a list with broken links fails the
    /// test instead of hanging it.
    func drainedFromBack(limit: Int = 1_000) -> [Element] {
        var values: [Element] = []
        while let node = last, values.count < limit {
            values.append(node.value)
            remove(node)
        }
        return values
    }
}

@Suite(.timeLimit(.minutes(5)))
struct LinkedListIntegrityTests {
    let list = LinkedList<Int>()

    @Test func removingAMiddleNodeRelinksItsNeighborsInBothDirections() {
        func makeList() -> LinkedList<Int> {
            let list = LinkedList<Int>()
            list.append(1)
            let node = list.append(2)
            list.append(3)
            list.remove(node)
            return list
        }

        #expect(makeList().drained() == [1, 3])
        #expect(makeList().drainedFromBack() == [3, 1])
    }

    @Test func removedNodeCanBeAppendedToAnotherList() {
        // Given
        list.append(1)
        let node = list.append(2)
        list.append(3)
        let other = LinkedList<Int>()

        // When the node moves between the lists, as the `TaskQueue` buckets do
        list.remove(node)
        other.append(node)

        // Then neither list sees the other's nodes
        #expect(other.count == 1)
        #expect(other.first === node)
        #expect(other.last === node)
        #expect(list.drained() == [1, 3])
    }

    @Test func removedNodeCanBePrependedBack() {
        // Given
        list.append(1)
        list.append(2)
        let node = list.append(3)

        // When
        list.remove(node)
        list.prepend(node)

        // Then
        #expect(list.first?.value == 3)
        #expect(list.last?.value == 2)
        #expect(list.drainedFromBack() == [2, 1, 3])
    }

    @Test func removingANodeTwiceIsANoOp() {
        // Given
        list.append(1)
        let node = list.append(2)
        list.append(3)

        // When
        list.remove(node)
        list.remove(node)

        // Then
        #expect(list.drained() == [1, 3])
    }

    @Test func listIsReusableAfterEveryNodeIsRemoved() {
        // Given
        let first = list.append(1)
        let middle = list.append(2)
        let last = list.append(3)

        // When
        list.remove(middle)
        list.remove(first)
        list.remove(last)

        // Then
        #expect(list.isEmpty)
        #expect(list.first == nil)
        #expect(list.last == nil)
        #expect(list.count == 0)

        // When
        list.append(4)
        list.prepend(LinkedList<Int>.Node(value: 5))

        // Then
        #expect(list.drained() == [5, 4])
    }

    @Test func linksStayConsistentAfterMixedOperations() {
        func makeList() -> LinkedList<Int> {
            let list = LinkedList<Int>()
            let one = list.append(1)
            let two = list.append(2)
            list.append(3)
            list.prepend(LinkedList<Int>.Node(value: 0))
            list.remove(two)
            list.moveToLast(one)
            return list
        }

        #expect(makeList().drained() == [0, 3, 1])
        #expect(makeList().drainedFromBack() == [1, 3, 0])
    }

    @Test func removeAllElementsDetachesEveryNode() {
        // Given
        let nodes = (1...3).map { list.append($0) }

        // When
        list.removeAllElements()

        // Then the nodes carry no links into the old list
        let other = LinkedList<Int>()
        other.append(nodes[1])
        other.append(nodes[0])
        #expect(other.drainedFromBack() == [1, 2])
    }

    /// The nodes link to each other strongly in both directions, so they
    /// would keep each other alive if the list didn't break the links.
    @Test func deallocatingTheListReleasesItsElements() {
        // Given
        var elements: [WeakRef<Element>] = []
        do {
            let list = LinkedList<Element>()
            for _ in 0..<3 {
                let element = Element()
                elements.append(WeakRef(element))
                list.append(element)
            }
            #expect(list.count == 3)
        }

        // Then
        #expect(elements.allSatisfy { $0.value == nil })
    }

    @Test func removingANodeReleasesItsElement() {
        // Given
        let list = LinkedList<Element>()
        list.append(Element())
        let removed = WeakRef<Element>()
        do {
            let element = Element()
            removed.value = element
            let node = list.append(element)
            list.append(Element())

            // When
            list.remove(node)
        }

        // Then
        #expect(removed.value == nil)
        #expect(list.count == 2)
    }

    @Test func removeAllElementsReleasesTheElements() {
        // Given
        let list = LinkedList<Element>()
        var elements: [WeakRef<Element>] = []
        for _ in 0..<3 {
            let element = Element()
            elements.append(WeakRef(element))
            list.append(element)
        }

        // When
        list.removeAllElements()

        // Then
        #expect(elements.allSatisfy { $0.value == nil })
    }

    private final class Element {}
}
