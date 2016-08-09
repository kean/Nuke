import Foundation

public func example(_ description: String, action: () -> ()) {
    print("\n-- \(description) --")
    action()
}
