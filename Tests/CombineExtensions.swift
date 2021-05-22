// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Nuke
import Combine

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
extension Publishers {
    public struct Anonymous<Output, Failure: Swift.Error>: Publisher {
        private var closure: (AnySubscriber<Output, Failure>) -> Void

        public init(closure: @escaping (AnySubscriber<Output, Failure>) -> Void) {
            self.closure = closure
        }

        public func receive<S>(subscriber: S) where S : Subscriber, Anonymous.Failure == S.Failure, Anonymous.Output == S.Input {
            let subscription = Subscriptions.Anonymous(subscriber: subscriber)
            subscriber.receive(subscription: subscription)
            subscription.start(closure)
        }
    }
}

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
extension Subscriptions {
    final class Anonymous<SubscriberType: Subscriber, Output, Failure>: Subscription where SubscriberType.Input == Output, Failure == SubscriberType.Failure {

        private var subscriber: SubscriberType?

        init(subscriber: SubscriberType) {
            self.subscriber = subscriber
        }

        func start(_ closure: @escaping (AnySubscriber<Output, Failure>) -> Void) {
            if let subscriber = subscriber {
                closure(AnySubscriber(subscriber))
            }
        }

        func request(_ demand: Subscribers.Demand) {
            // Ignore demand for now
        }

        func cancel() {
            self.subscriber = nil
        }

    }
}

@available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, *)
extension AnyPublisher {
    static func create(_ closure: @escaping (AnySubscriber<Output, Failure>) -> Void) -> AnyPublisher<Output, Failure> {
        return Publishers.Anonymous<Output, Failure>(closure: closure)
            .eraseToAnyPublisher()
    }

}
