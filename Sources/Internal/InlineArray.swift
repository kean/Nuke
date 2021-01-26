// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

// Inlines the first couple of elements to avoid allocating space on the heap.
struct InlineArray<Element>: Sequence {
    private(set) var count: Int = 0

    // Inlined elements
    private var e1: Element?
    private var e2: Element?

    // The remaining elements (allocated lazily)
    private var elements: ContiguousArray<Element>?

    init() {}

    subscript(index: Int) -> Element {
        get { element(at: index) }
        set { replaceElement(newValue, at: index) }
    }

    private mutating func replaceElement(_ element: Element, at index: Int) {
        switch index {
        case 0: e1 = element
        case 1: e2 = element
        default: elements![index - 2] = element
        }
    }

    private func element(at index: Int) -> Element {
        switch index {
        case 0: return e1!
        case 1: return e2!
        default: return elements![index - 2]
        }
    }

    mutating func append(_ element: Element) {
        switch count {
        case 0: e1 = element
        case 1: e2 = element
        default:
            if elements == nil {
                elements = ContiguousArray()
            }
            elements!.append(element)
        }
        count += 1
    }

    // MARK: Sequence

    __consuming func makeIterator() -> Iterator {
        Iterator(array: self)
    }

    struct Iterator: IteratorProtocol {
        private let array: InlineArray
        private var index: Int = 0

        init(array: InlineArray) {
            self.array = array
        }

        mutating func next() -> Element? {
            guard index < array.count else {
                return nil
            }
            defer { index += 1 }
            return array.element(at: index)
        }
    }
}
