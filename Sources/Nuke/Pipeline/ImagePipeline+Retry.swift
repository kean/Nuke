// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImagePipeline {
    /// Describes which failed loads the pipeline tries again, how many times,
    /// and how long it waits in between.
    ///
    /// Retries are off by default. Turn them on for every request with
    /// ``ImagePipeline/Configuration-swift.struct/retryPolicy``, or for one with
    /// ``ImageRequest/retryPolicy``:
    ///
    /// ```swift
    /// let pipeline = ImagePipeline {
    ///     $0.retryPolicy = .default
    /// }
    /// ```
    ///
    /// By default, the policy retries what a second attempt can fix: the network
    /// dropping out, a timeout, and the status codes in
    /// ``retryableStatusCodes``. It honors `Retry-After`, and it never repeats a
    /// request that isn't idempotent. To decide based on something else, such
    /// as an expired token, implement
    /// ``ImagePipeline/Delegate-swift.protocol/retryDecision(for:pipeline:)``.
    public struct RetryPolicy: Hashable, Sendable {
        /// The number of times a load is retried after the first attempt
        /// fails, so `2` means up to three attempts. `2` by default.
        public var maxRetryCount: Int

        /// The time to wait before a retry. Exponential by default: 0.5 s, 1 s,
        /// 2 s, and so on.
        public var backoff: Backoff

        /// The share of a delay that is taken off it at random, from 0 to 1.
        /// `0.2` by default, which waits for 80–100% of the delay.
        ///
        /// When a host goes down, every image on the screen fails at the same
        /// time. The jitter keeps them from all coming back at the same time.
        public var jitter: Double

        /// The longest the pipeline waits before a retry. 30 s by default.
        ///
        /// The backoff stops growing at this value. A server that asks to wait
        /// longer with `Retry-After` gets no retry: an image nobody is going to
        /// wait for isn't worth holding on to the task.
        public var maximumDelay: TimeInterval

        /// How long a load that failed because the device is offline waits for
        /// it to get back online. 30 s by default.
        ///
        /// The load is retried as soon as the device is online, and it fails
        /// with the original error if the time runs out. `0` treats these
        /// failures the same way as the rest, which spends the retries in a few
        /// seconds, with no chance of them succeeding.
        public var connectivityTimeout: TimeInterval

        /// The HTTP status codes worth retrying: `408`, `429`, `500`, `502`,
        /// `503`, and `504` by default.
        ///
        /// Applies to ``DataLoader/Error/statusCodeUnacceptable(_:)``, which
        /// is how ``DataLoader`` reports them.
        public var retryableStatusCodes: Set<Int>

        /// The `URLError` codes worth retrying. By default, the ones where the
        /// connection failed or dropped out. A `URLError` caused by the Low
        /// Data Mode or by a restriction on expensive networks is never
        /// retried: nothing changes until the settings do.
        public var retryableURLErrorCodes: Set<URLError.Code>

        /// How long to wait before a retry.
        public enum Backoff: Hashable, Sendable {
            /// The same delay before every retry, in seconds.
            case fixed(TimeInterval)
            /// A delay that grows with every retry, in seconds: `initial`,
            /// `initial * multiplier`, `initial * multiplier * multiplier`, and
            /// so on.
            case exponential(initial: TimeInterval, multiplier: Double)
        }

        /// The default policy: two retries, 0.5 s and 1 s apart.
        public static let `default` = RetryPolicy()

        /// A policy that never retries. Set it on a request to opt out of
        /// ``ImagePipeline/Configuration-swift.struct/retryPolicy``.
        ///
        /// - note: A load shared with another request can still be retried on
        /// behalf of that request. See ``ImageRequest/retryPolicy``.
        public static let disabled = RetryPolicy(maxRetryCount: 0)

        /// Initializes the policy. See the properties for what the parameters
        /// mean.
        public init(
            maxRetryCount: Int = 2,
            backoff: Backoff = .exponential(initial: 0.5, multiplier: 2),
            jitter: Double = 0.2,
            maximumDelay: TimeInterval = 30,
            connectivityTimeout: TimeInterval = 30,
            retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
            retryableURLErrorCodes: Set<URLError.Code> = [
                .badServerResponse,
                .callIsActive,
                .cannotConnectToHost,
                .cannotFindHost,
                .dataNotAllowed,
                .dnsLookupFailed,
                .networkConnectionLost,
                .notConnectedToInternet,
                .secureConnectionFailed,
                .timedOut
            ]
        ) {
            self.maxRetryCount = maxRetryCount
            self.backoff = backoff
            self.jitter = jitter
            self.maximumDelay = maximumDelay
            self.connectivityTimeout = connectivityTimeout
            self.retryableStatusCodes = retryableStatusCodes
            self.retryableURLErrorCodes = retryableURLErrorCodes
        }

        /// Returns what the policy says to do about the given failure.
        ///
        /// Call it from ``ImagePipeline/Delegate-swift.protocol/retryDecision(for:pipeline:)``
        /// to fall back to the policy.
        public func decision(for context: RetryContext) -> RetryDecision {
            guard context.retryCount < maxRetryCount, isRetryable(context) else {
                return .stop
            }
            let delay = delay(forRetry: context.retryCount)
            if connectivityTimeout > 0, context.isConnectivityFailure {
                return .retryWhenOnline(after: delay, timeout: connectivityTimeout)
            }
            guard let retryAfter = context.retryAfter else {
                return .retry(after: delay)
            }
            return retryAfter > maximumDelay ? .stop : .retry(after: max(delay, retryAfter))
        }

        /// The delay before the retry with the given index, starting at `0`.
        private func delay(forRetry index: Int) -> TimeInterval {
            let delay: TimeInterval = switch backoff {
            case .fixed(let delay): delay
            case let .exponential(initial, multiplier): initial * pow(multiplier, Double(index))
            }
            let capped = min(delay, maximumDelay)
            return jitter > 0 ? capped * (1 - .random(in: 0...min(jitter, 1))) : capped
        }

        private func isRetryable(_ context: RetryContext) -> Bool {
            guard context.isIdempotent, let error = context.error.dataLoadingError else {
                return false
            }
            if case .statusCodeUnacceptable(let statusCode)? = error as? DataLoader.Error {
                return retryableStatusCodes.contains(statusCode)
            }
            if let error = error as? URLError {
                return error.networkUnavailableReason == nil && retryableURLErrorCodes.contains(error.code)
            }
            return false
        }
    }

    /// What the pipeline does after an attempt to load an image fails.
    public enum RetryDecision: Hashable, Sendable {
        /// Fails the request with the error of the last attempt.
        case stop
        /// Loads the image again after the given number of seconds.
        case retry(after: TimeInterval)
        /// Waits for the given number of seconds, then for the device to be
        /// online, and loads the image again. The request fails with the error
        /// of the last attempt if the device is still offline after `timeout`
        /// seconds.
        ///
        /// The first wait is what stops a device that only looks online from
        /// retrying in a loop.
        case retryWhenOnline(after: TimeInterval, timeout: TimeInterval)
    }

    /// Describes an attempt to load an image that failed.
    public struct RetryContext: Sendable {
        /// The request that started the load. Coalesced requests share the
        /// load, and with it the retries, so it is the first one of them.
        public let request: ImageRequest
        /// The error the attempt failed with.
        public let error: ImagePipeline.Error
        /// The response to the failed attempt, if the data loader got one.
        ///
        /// Set for the responses that ``DataLoader`` rejects, which is where
        /// you can read the headers of a `503`. A custom ``DataLoading`` has
        /// a response here only if it passed one to `didReceiveData`.
        public let response: URLResponse?
        /// The number of retries so far: `0` when the first attempt fails.
        public let retryCount: Int
        /// The policy that applies to the load, if any: the one that allows the
        /// most retries of the requests that share it.
        public let policy: RetryPolicy?

        /// Initializes the context. The pipeline creates it for you – use this
        /// initializer to test the code that consumes it.
        public init(request: ImageRequest, error: ImagePipeline.Error, response: URLResponse? = nil, retryCount: Int = 0, policy: RetryPolicy? = nil) {
            self.request = request
            self.error = error
            self.response = response
            self.retryCount = retryCount
            self.policy = policy
        }

        /// The HTTP status code of the failed attempt, if there was a response.
        public var statusCode: Int? {
            if case .statusCodeUnacceptable(let statusCode)? = error.dataLoadingError as? DataLoader.Error {
                return statusCode
            }
            return (response as? HTTPURLResponse)?.statusCode
        }

        /// The time the server asked to wait with `Retry-After`, in seconds.
        /// `nil` if it didn't ask, or if the header can't be parsed.
        public var retryAfter: TimeInterval? {
            guard let value = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") else {
                return nil
            }
            // The header is either a number of seconds or an HTTP date.
            if let seconds = Int(value.trimmingCharacters(in: .whitespaces)) {
                return TimeInterval(max(0, seconds))
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return formatter.date(from: value).map { max(0, $0.timeIntervalSinceNow) }
        }

        /// `true` if the attempt failed because there is no way to reach the
        /// network, as opposed to the server being unreachable.
        var isConnectivityFailure: Bool {
            guard let error = error.dataLoadingError as? URLError else {
                return false
            }
            return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code)
        }

        /// `false` for the requests that a repeat could apply twice. The closures
        /// and the plain URLs have no method, and they only read.
        var isIdempotent: Bool {
            guard let method = request.urlRequest?.httpMethod?.uppercased() else {
                return true
            }
            return ["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"].contains(method)
        }
    }
}
