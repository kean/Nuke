// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

/// `DataLoader` implements only the task-level challenge method, so
/// `URLSession` sends it the session-wide challenges too, and it routes them
/// the way `URLSession` would.
@Suite(.timeLimit(.minutes(5)))
struct DataLoaderChallengeRoutingTests {
    private static let sessionWideAuthenticationMethods = [
        NSURLAuthenticationMethodServerTrust,
        NSURLAuthenticationMethodClientCertificate,
        NSURLAuthenticationMethodNTLM,
        NSURLAuthenticationMethodNegotiate
    ]

    @Test func sessionLevelChallengeIsForwardedToDelegate() async {
        // Given a delegate that implements only the session-level method
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodServerTrust) { _, _ in }
        let loader = makeStubLoader()
        let delegate = SessionLevelChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then the delegate rejects the server trust challenge
        #expect(delegate.challengeCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    @Test func taskLevelChallengeIsForwardedToDelegate() async {
        // Given a delegate that implements the task-level method
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodServerTrust) { _, _ in }
        let loader = makeStubLoader()
        let delegate = TaskLevelChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(delegate.challengeCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    @Test func sessionWideChallengeGoesToSessionLevelMethodFirst() async {
        // Given a delegate that implements both methods
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodServerTrust) { _, _ in }
        let loader = makeStubLoader()
        let delegate = BothLevelsChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then server trust goes to the session-level method, as with `URLSession`
        #expect(delegate.sessionLevelCount == 1)
        #expect(delegate.taskLevelCount == 0)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    /// `performDefaultHandling` means "as though this delegate method were not
    /// implemented", so a check in the task-level method still runs.
    @Test(arguments: sessionWideAuthenticationMethods)
    func sessionLevelDefaultHandlingGoesToTaskLevelMethod(authenticationMethod: String) async {
        // Given a delegate that passes on the challenge in the session-level
        // method and rejects it in the task-level one
        let url = StubURLProtocol.registerChallenge(authenticationMethod: authenticationMethod) { _, _ in }
        let loader = makeStubLoader()
        let delegate = BothLevelsChallengeDelegate(sessionLevel: .performDefaultHandling)
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(delegate.sessionLevelCount == 1)
        #expect(delegate.taskLevelCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    @Test func taskLevelMethodResolvesChallengeAfterSessionLevelDefaultHandling() async {
        // Given
        let resolution = OSAllocatedUnfairLock<ChallengeResolution?>(initialState: nil)
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodClientCertificate) { _, result in
            resolution.withLock { $0 = result }
        }
        let loader = makeStubLoader()
        loader.delegate = BothLevelsChallengeDelegate(
            sessionLevel: .performDefaultHandling,
            taskLevel: .useCredential,
            credential: URLCredential(user: "nuke", password: "secret", persistence: .none)
        )

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then the credential reaches the server
        #expect(resolution.withLock { $0 } == .useCredential(user: "nuke"))
        #expect(recorder.error == nil)
    }

    @Test func sessionLevelCredentialEndsRouting() async {
        // Given
        let resolution = OSAllocatedUnfairLock<ChallengeResolution?>(initialState: nil)
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodClientCertificate) { _, result in
            resolution.withLock { $0 = result }
        }
        let loader = makeStubLoader()
        let delegate = BothLevelsChallengeDelegate(
            sessionLevel: .useCredential,
            credential: URLCredential(user: "nuke", password: "secret", persistence: .none)
        )
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then the session-level method resolved it, as with `URLSession`
        #expect(delegate.sessionLevelCount == 1)
        #expect(delegate.taskLevelCount == 0)
        #expect(resolution.withLock { $0 } == .useCredential(user: "nuke"))
    }

    @Test func defaultHandlingAtBothLevelsResolvesChallengeOnce() async {
        // Given
        let resolutions = OSAllocatedUnfairLock<[ChallengeResolution]>(initialState: [])
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodServerTrust) { _, result in
            resolutions.withLock { $0.append(result) }
        }
        let loader = makeStubLoader()
        let delegate = BothLevelsChallengeDelegate(sessionLevel: .performDefaultHandling, taskLevel: .performDefaultHandling)
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(delegate.sessionLevelCount == 1)
        #expect(delegate.taskLevelCount == 1)
        #expect(resolutions.withLock { $0 } == [.performDefaultHandling])
        #expect(recorder.error == nil)
    }

    @Test func sessionLevelDefaultHandlingWithoutTaskLevelMethod() async {
        // Given a delegate that implements only the session-level method
        let resolution = OSAllocatedUnfairLock<ChallengeResolution?>(initialState: nil)
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodServerTrust) { _, result in
            resolution.withLock { $0 = result }
        }
        let loader = makeStubLoader()
        let delegate = SessionLevelChallengeDelegate(disposition: .performDefaultHandling)
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(delegate.challengeCount == 1)
        #expect(resolution.withLock { $0 } == .performDefaultHandling)
        #expect(recorder.error == nil)
    }

    @Test func taskLevelMethodIsCalledOnDelegateQueueAfterSessionLevelDefaultHandling() async {
        // Given a delegate that completes the session-level method on a queue of its own
        let url = StubURLProtocol.registerChallenge(authenticationMethod: NSURLAuthenticationMethodServerTrust) { _, _ in }
        let loader = makeStubLoader()
        let delegate = BothLevelsChallengeDelegate(sessionLevel: .performDefaultHandling, sessionLevelCompletionQueue: .global())
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then
        #expect(delegate.taskLevelCount == 1)
        #expect(delegate.taskLevelQueue === loader.session.delegateQueue)
    }

    @Test func taskSpecificChallengeGoesToTaskLevelMethod() async {
        // Given a delegate that implements both methods
        let url = StubURLProtocol.registerChallenge { _, _ in }
        let loader = makeStubLoader()
        let delegate = BothLevelsChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then HTTP Basic never goes to the session-level method
        #expect(delegate.sessionLevelCount == 0)
        #expect(delegate.taskLevelCount == 1)
        #expect((recorder.error as? URLError)?.code == .cancelled)
    }

    @Test func taskSpecificChallengeIsNotForwardedToSessionLevelMethod() async {
        // Given a delegate that implements only the session-level method
        let url = StubURLProtocol.registerChallenge { _, _ in }
        let loader = makeStubLoader()
        let delegate = SessionLevelChallengeDelegate()
        loader.delegate = delegate

        // When
        let recorder = LoadRecorder()
        await recorder.loadToCompletion(with: loader, request: URLRequest(url: url))

        // Then the challenge gets default handling
        #expect(delegate.challengeCount == 0)
        #expect(recorder.error == nil)
    }
}

// MARK: - Delegates

/// Implements only the session-level challenge method.
private final class SessionLevelChallengeDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    let disposition: URLSession.AuthChallengeDisposition
    var challengeCount: Int { _challengeCount.withLock { $0 } }
    private let _challengeCount = OSAllocatedUnfairLock(initialState: 0)

    init(disposition: URLSession.AuthChallengeDisposition = .cancelAuthenticationChallenge) {
        self.disposition = disposition
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        _challengeCount.withLock { $0 += 1 }
        completionHandler(disposition, nil)
    }
}

/// Implements only the task-level challenge method and rejects the challenge.
private final class TaskLevelChallengeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    var challengeCount: Int { _challengeCount.withLock { $0 } }
    private let _challengeCount = OSAllocatedUnfairLock(initialState: 0)

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        _challengeCount.withLock { $0 += 1 }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

/// Implements both challenge methods, which reject the challenge by default.
private final class BothLevelsChallengeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let sessionLevel: URLSession.AuthChallengeDisposition
    let taskLevel: URLSession.AuthChallengeDisposition
    let credential: URLCredential?
    let sessionLevelCompletionQueue: DispatchQueue?

    var sessionLevelCount: Int { _sessionLevelCount.withLock { $0 } }
    var taskLevelCount: Int { _taskLevelCount.withLock { $0 } }
    var taskLevelQueue: OperationQueue? { _taskLevelQueue.withLock { $0 } }
    private let _sessionLevelCount = OSAllocatedUnfairLock(initialState: 0)
    private let _taskLevelCount = OSAllocatedUnfairLock(initialState: 0)
    private let _taskLevelQueue = OSAllocatedUnfairLock<OperationQueue?>(uncheckedState: nil)

    init(
        sessionLevel: URLSession.AuthChallengeDisposition = .cancelAuthenticationChallenge,
        taskLevel: URLSession.AuthChallengeDisposition = .cancelAuthenticationChallenge,
        credential: URLCredential? = nil,
        sessionLevelCompletionQueue: DispatchQueue? = nil
    ) {
        self.sessionLevel = sessionLevel
        self.taskLevel = taskLevel
        self.credential = credential
        self.sessionLevelCompletionQueue = sessionLevelCompletionQueue
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        _sessionLevelCount.withLock { $0 += 1 }
        let (disposition, credential) = (sessionLevel, sessionLevel == .useCredential ? credential : nil)
        if let sessionLevelCompletionQueue {
            sessionLevelCompletionQueue.async { completionHandler(disposition, credential) }
        } else {
            completionHandler(disposition, credential)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        _taskLevelCount.withLock { $0 += 1 }
        _taskLevelQueue.withLockUnchecked { $0 = OperationQueue.current }
        completionHandler(taskLevel, taskLevel == .useCredential ? credential : nil)
    }
}
