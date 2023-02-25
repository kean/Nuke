// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// A doubly linked list.
final class LinkedList<Element> {
    // first <-> node <-> ... <-> last
    private(set) var first: Node?
    private(set) var last: Node?

    deinit {
        // This way we make sure that the deallocations do no happen recursively
        // (and potentially overflow the stack).
        removeAllElements()
    }

    var isEmpty: Bool {
        last == nil
    }

    /// Adds an element to the end of the list.
    @discardableResult
    func append(_ element: Element) -> Node {
        let node = Node(value: element)
        append(node)
        return node
    }

    /// Adds a node to the end of the list.
    func append(_ node: Node) {
        if let last = last {
            last.next = node
            node.previous = last
            self.last = node
        } else {
            last = node
            first = node
        }
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
    }

    final class Node {
        let value: Element
        fileprivate var next: Node?
        fileprivate var previous: Node?

        init(value: Element) {
            self.value = value
        }
    }
}
