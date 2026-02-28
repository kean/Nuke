// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

final class TestExpectation: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State = .idle

    private enum State {
        case idle
        case fulfilled
        case awaiting(CheckedContinuation<Void, Never>)
    }

    init() {}

    func fulfill() {
        lock.lock()
        switch state {
        case .idle:
            state = .fulfilled
            lock.unlock()
        case .awaiting(let continuation):
            state = .fulfilled
            lock.unlock()
            continuation.resume()
        case .fulfilled:
            lock.unlock()
        }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            switch state {
            case .idle:
                state = .awaiting(continuation)
                lock.unlock()
            case .fulfilled:
                lock.unlock()
                continuation.resume()
            case .awaiting:
                lock.unlock()
                preconditionFailure("wait() called multiple times")
            }
        }
    }
}

extension TestExpectation {
    convenience init(notification name: Notification.Name, object: AnyObject? = nil) {
        self.init()
        let ref = TokenRef()
        ref.token = NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
            if let token = ref.token { NotificationCenter.default.removeObserver(token) }
            self?.fulfill()
        }
    }
}

private final class TokenRef: @unchecked Sendable {
    var token: NSObjectProtocol?
}

func notification(_ name: Notification.Name, object: AnyObject? = nil, while action: () -> Void = {}) async {
    let expectation = TestExpectation(notification: name, object: object)
    action()
    await expectation.wait()
}
