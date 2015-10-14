import Foundation

public func example(description: String, action: () -> ()) {
    print("\n-- \(description) --")
    action()
}
