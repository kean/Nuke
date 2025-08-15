import Foundation

/// Optimized for a scenario when there is only one subscriber (or two in the
/// case of prefetching).
struct JobSubsciberSet<Element> {
    private var inline: (Element?, Element?)
    private var more: [Int: Element]?
    private var nextIndex = 2

    private(set) var count: Int = 0

    mutating func add(_ element: Element) -> Int {
        count += 1
        if inline.0 == nil {
            inline.0 = element
            return 0
        } else if inline.1 == nil {
            inline.1 = element
            return 1
        } else {
            if more == nil { more = [:] }
            let index = nextIndex
            nextIndex += 1
            more![index] = element
            return index
        }
    }

    mutating func remove(at index: Int) {
        count -= 1
        if index == 0 {
            inline.0 = nil
        } else if index == 1 {
            inline.1 = nil
        } else {
            more?[index] = nil
        }
    }

    func forEach(_ closure: (Element) -> Void) {
        if let sub = inline.0 { closure(sub) }
        if let sub = inline.1 { closure(sub) }
        if let more {
            for (_, value) in more {
                closure(value)
            }
        }
    }
}
