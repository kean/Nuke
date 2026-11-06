// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// What ``ImagePipeline/RetryPolicy`` decides for a failure, on its own.
@Suite(.timeLimit(.minutes(5)))
struct RetryPolicyTests {
    private typealias Policy = ImagePipeline.RetryPolicy
    private typealias Context = ImagePipeline.RetryContext

    /// A policy with no randomness in it, and no special case for being offline.
    private let policy = Policy(backoff: .fixed(1), jitter: 0, connectivityTimeout: 0)

    private func failure(_ code: URLError.Code) -> ImagePipeline.Error {
        .dataLoadingFailed(error: URLError(code))
    }

    private func failure(statusCode: Int) -> ImagePipeline.Error {
        .dataLoadingFailed(error: DataLoader.Error.statusCodeUnacceptable(statusCode))
    }

    private func context(_ error: ImagePipeline.Error, retryCount: Int = 0, response: URLResponse? = nil, request: ImageRequest = Test.request) -> Context {
        Context(request: request, error: error, response: response, retryCount: retryCount)
    }

    private func response(statusCode: Int = 503, retryAfter: String) -> HTTPURLResponse {
        HTTPURLResponse(url: Test.url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": retryAfter])!
    }

    // MARK: Defaults

    @Test func defaultPolicy() {
        let policy = Policy.default
        #expect(policy.maxRetryCount == 2)
        #expect(policy.backoff == .exponential(initial: 0.5, multiplier: 2))
        #expect(policy.jitter == 0.2)
        #expect(policy.maximumDelay == 30)
        #expect(policy.connectivityTimeout == 30)
        #expect(policy.retryableStatusCodes == [408, 429, 500, 502, 503, 504])
    }

    @Test func disabledPolicyNeverRetries() {
        #expect(Policy.disabled.decision(for: context(failure(.timedOut))) == .stop)
        #expect(Policy.disabled.decision(for: context(failure(statusCode: 503))) == .stop)
    }

    // MARK: What is Retried

    @Test(arguments: [408, 429, 500, 502, 503, 504])
    func transientStatusCodeIsRetried(statusCode: Int) {
        #expect(policy.decision(for: context(failure(statusCode: statusCode))) == .retry(after: 1))
    }

    @Test(arguments: [400, 401, 403, 404, 410, 416, 501, 505])
    func permanentStatusCodeIsNotRetried(statusCode: Int) {
        #expect(policy.decision(for: context(failure(statusCode: statusCode))) == .stop)
    }

    @Test(arguments: [
        URLError.Code.timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        .networkConnectionLost, .notConnectedToInternet, .secureConnectionFailed,
        .badServerResponse, .dataNotAllowed, .callIsActive
    ])
    func transientURLErrorIsRetried(code: URLError.Code) {
        #expect(policy.decision(for: context(failure(code))) == .retry(after: 1))
    }

    @Test(arguments: [
        URLError.Code.cancelled, .badURL, .unsupportedURL, .userAuthenticationRequired,
        .appTransportSecurityRequiresSecureConnection, .serverCertificateUntrusted, .fileDoesNotExist
    ])
    func permanentURLErrorIsNotRetried(code: URLError.Code) {
        #expect(policy.decision(for: context(failure(code))) == .stop)
    }

    @Test func customCodesReplaceTheDefaults() {
        var policy = policy
        policy.retryableStatusCodes = [404]
        policy.retryableURLErrorCodes = [.cannotDecodeRawData]

        #expect(policy.decision(for: context(failure(statusCode: 404))) == .retry(after: 1))
        #expect(policy.decision(for: context(failure(.cannotDecodeRawData))) == .retry(after: 1))
        #expect(policy.decision(for: context(failure(statusCode: 503))) == .stop)
        #expect(policy.decision(for: context(failure(.timedOut))) == .stop)
    }

    @Test func errorsOfAnotherKindAreNotRetried() {
        let errors: [ImagePipeline.Error] = [
            .dataIsEmpty,
            .dataMissingInCache,
            .dataDownloadExceededMaximumSize,
            .cancelled,
            .dataLoadingFailed(error: NSError(domain: "custom", code: 1))
        ]
        for error in errors {
            #expect(policy.decision(for: context(error)) == .stop)
        }
    }

    @Test func errorFromLowDataModeIsNotRetried() {
        // Nothing is going to change until the person changes the settings.
        let error = URLError(.notConnectedToInternet, userInfo: [
            NSURLErrorNetworkUnavailableReasonKey: URLError.NetworkUnavailableReason.constrained.rawValue
        ])
        #expect(error.networkUnavailableReason == .constrained)
        #expect(policy.decision(for: context(.dataLoadingFailed(error: error))) == .stop)
    }

    @Test func bridgedErrorsAreRecognized() {
        // This is what a closure or a custom data loader often has at hand.
        let error = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)
        #expect(policy.decision(for: context(.dataLoadingFailed(error: error))) == .retry(after: 1))
    }

    @Test(arguments: ["POST", "PATCH", "post"])
    func requestThatIsNotIdempotentIsNotRetried(method: String) {
        var urlRequest = URLRequest(url: Test.url)
        urlRequest.httpMethod = method
        let context = context(failure(.timedOut), request: ImageRequest(urlRequest: urlRequest))
        #expect(policy.decision(for: context) == .stop)
    }

    @Test(arguments: ["GET", "HEAD", "PUT", "DELETE"])
    func idempotentRequestIsRetried(method: String) {
        var urlRequest = URLRequest(url: Test.url)
        urlRequest.httpMethod = method
        let context = context(failure(.timedOut), request: ImageRequest(urlRequest: urlRequest))
        #expect(policy.decision(for: context) == .retry(after: 1))
    }

    @Test func requestWithoutAMethodIsRetried() {
        let request = ImageRequest(id: "a", data: { Data() })
        #expect(policy.decision(for: context(failure(.timedOut), request: request)) == .retry(after: 1))
    }

    // MARK: How Many Times

    @Test func stopsAtMaxRetryCount() {
        var policy = policy
        policy.maxRetryCount = 3
        #expect(policy.decision(for: context(failure(.timedOut), retryCount: 2)) == .retry(after: 1))
        #expect(policy.decision(for: context(failure(.timedOut), retryCount: 3)) == .stop)
        #expect(policy.decision(for: context(failure(.timedOut), retryCount: 4)) == .stop)
    }

    // MARK: Delays

    @Test func exponentialBackoff() {
        let policy = Policy(maxRetryCount: 10, backoff: .exponential(initial: 0.5, multiplier: 2), jitter: 0, connectivityTimeout: 0)
        let delays = (0..<4).map { policy.decision(for: context(failure(.timedOut), retryCount: $0)) }
        #expect(delays == [.retry(after: 0.5), .retry(after: 1), .retry(after: 2), .retry(after: 4)])
    }

    @Test func maximumDelayCapsTheBackoff() {
        let policy = Policy(maxRetryCount: 2000, backoff: .exponential(initial: 1, multiplier: 2), jitter: 0, maximumDelay: 5, connectivityTimeout: 0)
        #expect(policy.decision(for: context(failure(.timedOut), retryCount: 10)) == .retry(after: 5))
        // Far past the point where the number is representable
        #expect(policy.decision(for: context(failure(.timedOut), retryCount: 1500)) == .retry(after: 5))
    }

    @Test func jitterTakesTheDelayDownAndNeverUp() throws {
        let policy = Policy(backoff: .fixed(1), jitter: 0.25, connectivityTimeout: 0)
        var delays: Set<TimeInterval> = []
        for _ in 0..<500 {
            guard case .retry(let delay) = policy.decision(for: context(failure(.timedOut))) else {
                Issue.record("Expected a retry")
                return
            }
            delays.insert(delay)
        }
        #expect(delays.count > 1)
        #expect(try #require(delays.min()) >= 0.75)
        #expect(try #require(delays.max()) <= 1)
    }

    @Test func jitterAboveOneDoesNotMakeADelayNegative() {
        let policy = Policy(backoff: .fixed(1), jitter: 5, connectivityTimeout: 0)
        for _ in 0..<100 {
            guard case .retry(let delay) = policy.decision(for: context(failure(.timedOut))) else {
                Issue.record("Expected a retry")
                return
            }
            #expect(delay >= 0)
        }
    }

    // MARK: Retry-After

    @Test func retryAfterInSeconds() {
        let context = context(failure(statusCode: 503), response: response(retryAfter: "7"))
        #expect(context.retryAfter == 7)
        #expect(policy.decision(for: context) == .retry(after: 7))
    }

    @Test func retryAfterAsAnHTTPDate() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let date = formatter.string(from: Date().addingTimeInterval(20))

        let context = context(failure(statusCode: 429), response: response(statusCode: 429, retryAfter: date))
        let retryAfter = try #require(context.retryAfter)

        #expect((18...20).contains(retryAfter))
    }

    @Test func retryAfterInThePastIsZero() {
        let date = "Wed, 21 Oct 2015 07:28:00 GMT"
        #expect(context(failure(statusCode: 503), response: response(retryAfter: date)).retryAfter == 0)
    }

    @Test(arguments: ["soon", "", "1.5", "nan"])
    func retryAfterThatCannotBeParsedIsIgnored(value: String) {
        let context = context(failure(statusCode: 503), response: response(retryAfter: value))
        #expect(context.retryAfter == nil)
        #expect(policy.decision(for: context) == .retry(after: 1))
    }

    @Test func noRetryAfterWithoutAnHTTPResponse() {
        #expect(context(failure(.timedOut)).retryAfter == nil)
        let response = URLResponse(url: Test.url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        #expect(context(failure(.timedOut), response: response).retryAfter == nil)
    }

    @Test func backoffWinsOverAShorterRetryAfter() {
        let context = context(failure(statusCode: 503), retryCount: 0, response: response(retryAfter: "0"))
        #expect(policy.decision(for: context) == .retry(after: 1))
    }

    @Test func retryAfterAboveTheMaximumDelayStops() {
        var policy = policy
        policy.maximumDelay = 30
        #expect(policy.decision(for: context(failure(statusCode: 503), response: response(retryAfter: "30"))) == .retry(after: 30))
        #expect(policy.decision(for: context(failure(statusCode: 503), response: response(retryAfter: "31"))) == .stop)
    }

    // MARK: Connectivity

    @Test(arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed])
    func offlineFailureWaitsForConnectivity(code: URLError.Code) {
        let policy = Policy(backoff: .fixed(1), jitter: 0, connectivityTimeout: 15)
        #expect(policy.decision(for: context(failure(code))) == .retryWhenOnline(after: 1, timeout: 15))
    }

    @Test func otherFailuresDoNotWaitForConnectivity() {
        let policy = Policy(backoff: .fixed(1), jitter: 0, connectivityTimeout: 15)
        #expect(policy.decision(for: context(failure(.timedOut))) == .retry(after: 1))
        #expect(policy.decision(for: context(failure(statusCode: 503))) == .retry(after: 1))
    }

    @Test func offlineFailureStopsAtMaxRetryCount() {
        let policy = Policy(maxRetryCount: 1, backoff: .fixed(1), jitter: 0, connectivityTimeout: 15)
        #expect(policy.decision(for: context(failure(.notConnectedToInternet), retryCount: 1)) == .stop)
    }

    // MARK: Context

    @Test func statusCodeComesFromTheErrorOrTheResponse() {
        #expect(context(failure(statusCode: 404)).statusCode == 404)
        #expect(context(failure(.timedOut), response: response(statusCode: 503, retryAfter: "1")).statusCode == 503)
        #expect(context(failure(.timedOut)).statusCode == nil)
    }

    // MARK: ImageRequest

    @Test func requestHasNoPolicyByDefault() {
        #expect(Test.request.retryPolicy == nil)
    }

    @Test func requestKeepsThePolicyAcrossCopies() {
        var request = Test.request
        request.retryPolicy = .immediate(5)
        var copy = request
        copy.priority = .high
        #expect(copy.retryPolicy == .immediate(5))

        copy.retryPolicy = nil
        #expect(copy.retryPolicy == nil)
        #expect(request.retryPolicy == .immediate(5))
    }

    @Test func policyDoesNotChangeWhatTheRequestLoads() {
        var request = Test.request
        request.retryPolicy = .immediate(5)
        // A policy doesn't stop requests from coalescing, which the keys decide.
        #expect(TaskLoadImageKey(request) == TaskLoadImageKey(Test.request))
        #expect(TaskFetchOriginalDataKey(request) == TaskFetchOriginalDataKey(Test.request))
    }
}
