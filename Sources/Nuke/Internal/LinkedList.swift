// The MIT License (MIT)
//
// Copyright (c) 2015-2025 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A doubly linked list.
final class LinkedList<Element: Sendable> {
    // first <-> node <-> ... <-> last
    private(set) var first: Node?
    private(set) var last: Node?
    private(set) var count = 0

    var isEmpty: Bool { last == nil }

    deinit {
        // This way we make sure that the deallocations do no happen recursively
        // (and potentially overflow the stack).
        removeAllElements()
    }

    /// Adds an element to the end of the list.
    @discardableResult func append(_ element: Element) -> Node {
        let node = Node(element)
        append(node)
        return node
    }

    /// Adds a node to the end of the list.
    func append(_ node: Node) {
        if let last {
            last.next = node
            node.previous = last
            self.last = node
        } else {
            last = node
            first = node
        }
        count += 1
    }

    /// Adds a node to the beginning of the list.
    func prepend(_ node: Node) {
        if let first {
            node.next = first
            first.previous = node
            self.first = node
        } else {
            first = node
            last = node
        }
        count += 1
    }

    func popLast() -> Node? {
        guard let last else {
            return nil
        }
        remove(last)
        return last
    }

    func remove(_ node: Node) {
        node.next?.previous = node.previous // node.previous is nil if node=first
        node.previous?.next = node.next // node.next is nil if node=last
        if node === last {
            last = node.previous
        }
        if node === first {
            first = node.next
        }
        node.next = nil
        node.previous = nil
        count -= 1
    }

    func removeAllElements() {
        // avoid recursive Nodes deallocation
        var node = first
        while let next = node?.next {
            node?.next = nil
            next.previous = nil
            node = next
        }
        last = nil
        first = nil
        count = 0
    }

    final class Node {
        var value: Element
        fileprivate(set) var next: Node?
        fileprivate(set) var previous: Node?

        init(_ value: Element) { self.value = value }
    }
}
