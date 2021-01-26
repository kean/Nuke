// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

// A set which inlines the first couple of elements and avoid any heap allocations.
struct SmallArray<Element> {
    private(set) var count: Int = 0

    // Inlined elements
    private var e1: Element?
    private var e2: Element?

    // The remaining elements (allocated lazily)
    private var array: ContiguousArray<Element?>?

    var isEmpty: Bool {
        count == 0 // swiftlint:disable:this all
    }

    init() {}

    mutating func insert(_ element: Element) {
        switch count {
        case 0:
            e1 = element
        case 1:
            e2 = element
        default:
            if array == nil {
                array = ContiguousArray()
            }
            array!.append(element)
        }
        count += 1
    }

    mutating func removeElement(at index: Int) -> Element? {
        switch index {
        case 0:
            guard let element = e1 else { return nil }
            e1 = nil
            count -= 1
            return element
        case 1:
            guard let element = e2 else { return nil }
            e2 = nil
            count -= 1
            return element
        default:
            guard let element = array![index - 2] else { return nil }
            array![index - 2] = nil
            count -= 1
            return element
        }
    }

    mutating func updateElement(at index: Int, _ transform: (inout Element) -> Void) {
        switch index {
        case 0:
            if e1 != nil {
                transform(&e1!)
            }
        case 1:
            if e2 != nil {
                transform(&e2!)
            }
        default:
            if var value = array![index - 2] {
                transform(&value)
                array![index - 2] = value
            }
        }
    }

    func enumerateValues(_ closure: (Element) -> Void) {
        if let element = e1 {
            closure(element)
        }
        if let element = e2 {
            closure(element)
        }
        if array != nil {
            for element in array! where element != nil {
                closure(element!)
            }
        }
    }
}
