// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import ImageIO
import Nuke
import os
import UniformTypeIdentifiers

/// A data loader for tests and previews: it answers with responses you choose,
/// and never touches the network.
///
/// ```swift
/// let dataLoader = StubDataLoader()
/// dataLoader.stub(brokenURL, with: .status(404))
///
/// let pipeline = ImagePipeline.stubbed(dataLoader)
/// let image = try await pipeline.image(for: url) // A generated image
/// #expect(dataLoader.requests.map(\.url) == [url])
/// ```
public final class StubDataLoader: DataLoading, Sendable {
    /// What the loader answers a request with.
    public enum Response: Sendable {
        /// `200 OK` with the given body.
        case data(Data, mimeType: String? = nil)
        /// The given status code and no body. Anything but a `2xx` fails with
        /// ``DataLoader/Error/statusCodeUnacceptable(_:)``, like ``DataLoader``.
        case status(Int)
        /// The request fails with the given error, such as a `URLError`.
        case failure(any Error)
        /// The request never finishes, which is how to test a loading state
        /// or a cancellation.
        case hanging

        /// A generated PNG of the given size in pixels.
        public static func image(width: Int = 1, height: Int = 1) -> Response {
            .data(Self.makePNG(width: width, height: height), mimeType: "image/png")
        }

        private static func makePNG(width: Int, height: Int) -> Data {
            let data = NSMutableData()
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                return Data()
            }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            return data as Data
        }
    }

    private struct State {
        var responses: [URL: Response] = [:]
        var requests: [URLRequest] = []
    }

    private let defaultResponse: Response
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// The requests the loader received, in order.
    public var requests: [URLRequest] { state.withLock { $0.requests } }

    /// - parameter defaultResponse: The answer to a URL with no stub. By
    /// default, a generated image, so that every request succeeds.
    public init(defaultResponse: Response = .image()) {
        self.defaultResponse = defaultResponse
    }

    /// Sets the answer to the requests with the given URL.
    public func stub(_ url: URL, with response: Response) {
        state.withLock { $0.responses[url] = response }
    }

    public func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable ((any Error)?) -> Void
    ) -> any Cancellable {
        let response = state.withLock {
            $0.requests.append(request)
            return request.url.flatMap { [responses = $0.responses] in responses[$0] } ?? defaultResponse
        }
        let url = request.url ?? URL(fileURLWithPath: "/")
        let task = Task {
            switch response {
            case let .data(data, mimeType):
                let headers = ["Content-Length": "\(data.count)", "Content-Type": mimeType ?? "application/octet-stream"]
                if let urlResponse = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers), !data.isEmpty {
                    didReceiveData(data, urlResponse)
                }
                completion(nil)
            case let .status(code):
                completion((200..<300).contains(code) ? nil : DataLoader.Error.statusCodeUnacceptable(code))
            case let .failure(error):
                completion(error)
            case .hanging:
                break
            }
        }
        return StubTask(task: task)
    }

    private struct StubTask: Cancellable {
        let task: Task<Void, Never>

        func cancel() {
            task.cancel()
        }
    }
}

extension ImagePipeline {
    /// Creates a pipeline for tests and previews: it loads with the given
    /// stub, and has no caches, so tests can't affect one another, and nothing
    /// stays on the disk.
    ///
    /// ```swift
    /// LazyImage(url: url).pipeline(.stubbed(StubDataLoader()))
    /// ```
    ///
    /// - parameters:
    ///   - dataLoader: Answers the requests.
    ///   - configure: Changes the configuration further.
    nonisolated public static func stubbed(
        _ dataLoader: StubDataLoader = StubDataLoader(),
        configure: (inout ImagePipeline.Configuration) -> Void = { _ in }
    ) -> ImagePipeline {
        ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.dataCache = nil
            configure(&$0)
        }
    }
}
