// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

// BUG: `DataLoader.delegate` never receives the session-level authentication
// challenge `urlSession(_:didReceive:completionHandler:)`, so a delegate that
// pins certificates there is silently bypassed.
//
// Sources/Nuke/Loading/DataLoader.swift — `_DataLoader` implements only the
// task-level `urlSession(_:task:didReceive:completionHandler:)` and forwards it
// to `(delegate as? URLSessionTaskDelegate)?.urlSession?(_:task:didReceive:...)`.
// Because `_DataLoader` doesn't implement the session-level method, `URLSession`
// routes session-wide challenges (server trust, client certificates) to the
// task-level one; a user delegate that implements only the session-level
// method — the `URLSessionDelegate` way of doing SSL pinning, and the only
// challenge method `URLSessionDelegate` (the type of `DataLoader.delegate`)
// has — never hears about the challenge, and the loader falls back to
// `.performDefaultHandling`.
//
// The documentation says the delegate can be used for "handling authentication
// challenges", and CHANGELOG (Nuke 11) says `DataLoader/delegate` "now gets
// called for all `URLSession/delegate` methods".
//
// Expected: the delegate is asked about the server-trust challenge, rejects
//           it, and the load fails with `URLError.cancelled` (which is what a
//           plain `URLSession` with the same delegate does — see the control
//           test below, which passes).
// Actual:   the delegate is never called; the challenge gets default handling
//           and the load succeeds.

@Suite(.timeLimit(.minutes(2)))
struct DataLoaderSessionLevelChallengeBugTests {
    @Test func sessionLevelChallengeReachesDataLoaderDelegate() async {
        // GIVEN a delegate that pins certificates by rejecting server trust
        let url = _ChallengingProtocol.register()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [_ChallengingProtocol.self]
        let loader = DataLoader(configuration: configuration)
        let delegate = _PinningDelegate()
        loader.delegate = delegate

        // WHEN
        let outcome = await _load(url, with: loader)

        // THEN the delegate decides
        #expect(delegate.challengeCount == 1)
        #expect(outcome.errorCode == .cancelled)
        #expect(outcome.body.isEmpty)
    }

    /// Control: the same delegate on a plain `URLSession` is asked, and the
    /// load fails. (Passes.)
    @Test func sessionLevelChallengeReachesPlainURLSessionDelegate() async {
        let url = _ChallengingProtocol.register()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [_ChallengingProtocol.self]
        let delegate = _PinningDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let errorCode: URLError.Code? = await withCheckedContinuation { continuation in
            session.dataTask(with: url) { _, _, error in
                continuation.resume(returning: (error as? URLError)?.code)
            }.resume()
        }

        #expect(delegate.challengeCount == 1)
        #expect(errorCode == .cancelled)
    }
}

private struct _Outcome: Sendable {
    var body = Data()
    var errorCode: URLError.Code?
}

private func _load(_ url: URL, with loader: DataLoader) async -> _Outcome {
    let body = OSAllocatedUnfairLock(initialState: Data())
    return await withCheckedContinuation { continuation in
        _ = loader.loadData(with: URLRequest(url: url), didReceiveData: { data, _ in
            body.withLock { $0.append(data) }
        }, completion: { error in
            continuation.resume(returning: _Outcome(body: body.withLock { $0 }, errorCode: (error as? URLError)?.code))
        })
    }
}

/// Implements only the session-level challenge method.
private final class _PinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let _challengeCount = OSAllocatedUnfairLock(initialState: 0)
    var challengeCount: Int { _challengeCount.withLock { $0 } }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        _challengeCount.withLock { $0 += 1 }
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

/// Challenges every request for server trust, then responds with "trusted".
private final class _ChallengingProtocol: URLProtocol, URLAuthenticationChallengeSender, @unchecked Sendable {
    static func register() -> URL {
        URL(string: "pinning://\(UUID().uuidString.lowercased())/image.jpeg")!
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "pinning"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let space = URLProtectionSpace(host: request.url?.host ?? "", port: 443, protocol: "https", realm: nil, authenticationMethod: NSURLAuthenticationMethodServerTrust)
        let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: self)
        client?.urlProtocol(self, didReceive: challenge)
    }

    override func stopLoading() {}

    private func respond() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "7"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("trusted".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) { respond() }
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) { respond() }
    func cancel(_ challenge: URLAuthenticationChallenge) { client?.urlProtocol(self, didFailWithError: URLError(.cancelled)) }
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) { respond() }
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) { respond() }
}
