// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

/// Serves `stub://` requests with the handler registered under the URL.
///
/// Every registration gets a URL of its own, and the handlers are kept
/// behind a lock, so the tests that use it can run in parallel.
final class StubURLProtocol: URLProtocol, URLAuthenticationChallengeSender, @unchecked Sendable {
    typealias Handler = @Sendable (StubURLProtocol) -> Void

    private static let handlers = OSAllocatedUnfairLock<[URL: Handler]>(initialState: [:])
    private let onChallengeResolved = OSAllocatedUnfairLock<(@Sendable (ChallengeResolution) -> Void)?>(initialState: nil)

    /// Registers the handler under a new unique URL.
    static func register(_ handler: @escaping Handler) -> URL {
        let url = URL(string: "stub://\(UUID().uuidString.lowercased())/image.jpeg")!
        handlers.withLock { $0[url] = handler }
        return url
    }

    /// Registers a "302 Found" redirecting to the given URL.
    static func registerRedirect(to destination: URL) -> URL {
        register { stub in
            let response = HTTPURLResponse(url: stub.request.url!, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": destination.absoluteString])!
            stub.client?.urlProtocol(stub, wasRedirectedTo: URLRequest(url: destination), redirectResponse: response)
        }
    }

    /// Registers a server that challenges the client with the given
    /// authentication method, HTTP Basic by default, and responds with
    /// "authorized" once the challenge sender is told how to proceed. (When
    /// the client cancels the challenge, `URLSession` cancels the task instead
    /// of telling the sender.)
    static func registerChallenge(
        authenticationMethod: String = NSURLAuthenticationMethodHTTPBasic,
        _ onResolved: @escaping @Sendable (StubURLProtocol, ChallengeResolution) -> Void
    ) -> URL {
        register { stub in
            stub.onChallengeResolved.withLock {
                $0 = { resolution in
                    onResolved(stub, resolution)
                    stub.respond(chunks: [Data("authorized".utf8)])
                }
            }
            let space = URLProtectionSpace(host: stub.request.url?.host ?? "", port: 443, protocol: "https", realm: "Nuke", authenticationMethod: authenticationMethod)
            let challenge = URLAuthenticationChallenge(protectionSpace: space, proposedCredential: nil, previousFailureCount: 0, failureResponse: nil, error: nil, sender: stub)
            stub.client?.urlProtocol(stub, didReceive: challenge)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.scheme == "stub"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let handler = Self.handlers.withLock({ $0[url] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        handler(self)
    }

    override func stopLoading() {}

    // MARK: Responding

    func sendResponse(statusCode: Int = 200, headers: [String: String] = [:]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func send(_ chunk: Data) {
        client?.urlProtocol(self, didLoad: chunk)
    }

    func finish() {
        client?.urlProtocolDidFinishLoading(self)
    }

    func fail(_ error: URLError) {
        client?.urlProtocol(self, didFailWithError: error)
    }

    func respond(statusCode: Int = 200, headers: [String: String] = [:], chunks: [Data]) {
        var headers = headers
        if headers["Content-Length"] == nil {
            headers["Content-Length"] = String(chunks.reduce(0) { $0 + $1.count })
        }
        sendResponse(statusCode: statusCode, headers: headers)
        chunks.forEach(send)
        finish()
    }

    // MARK: URLAuthenticationChallengeSender

    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        resolve(.useCredential(user: credential.user))
    }

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        resolve(.continueWithoutCredential)
    }

    func cancel(_ challenge: URLAuthenticationChallenge) {
        resolve(.cancel)
    }

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        resolve(.performDefaultHandling)
    }

    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        resolve(.rejectProtectionSpace)
    }

    private func resolve(_ resolution: ChallengeResolution) {
        onChallengeResolved.withLock { $0 }?(resolution)
    }
}

/// How the server-side sender of an authentication challenge was told to
/// proceed.
enum ChallengeResolution: Equatable, Sendable {
    case useCredential(user: String?)
    case continueWithoutCredential
    case cancel
    case performDefaultHandling
    case rejectProtectionSpace
}
