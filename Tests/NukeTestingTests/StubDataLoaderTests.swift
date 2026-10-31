// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import NukeTesting
import Testing

@Suite(.timeLimit(.minutes(1)))
struct StubDataLoaderTests {
    private let dataLoader = StubDataLoader()
    private let url = URL(string: "https://example.com/image.png")!

    @Test func everyRequestSucceedsByDefault() async throws {
        let response = try await ImagePipeline.stubbed(dataLoader).imageTask(with: url).response

        #expect(response.container.type == .png)
        #expect((response.urlResponse as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test func imageHasTheGivenSize() async throws {
        dataLoader.stub(url, with: .image(width: 40, height: 20))

        let response = try await ImagePipeline.stubbed(dataLoader).imageTask(with: url).response

        #expect(response.image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width == 40)
    }

    @Test func recordsTheRequests() async throws {
        let pipeline = ImagePipeline.stubbed(dataLoader)

        _ = try await pipeline.image(for: url)
        _ = try await pipeline.image(for: url) // There's no cache

        #expect(dataLoader.requests.map(\.url) == [url, url])
    }

    @Test func statusCodeFailsLikeTheDataLoader() async {
        dataLoader.stub(url, with: .status(404))

        await #expect {
            _ = try await ImagePipeline.stubbed(dataLoader).image(for: url)
        } throws: { error in
            guard case .dataLoadingFailed(let underlying)? = error as? ImagePipeline.Error,
                  case .statusCodeUnacceptable(404)? = underlying as? DataLoader.Error else {
                return false
            }
            return true
        }
    }

    @Test func failureIsWrapped() async {
        dataLoader.stub(url, with: .failure(URLError(.notConnectedToInternet)))

        await #expect {
            _ = try await ImagePipeline.stubbed(dataLoader).image(for: url)
        } throws: { error in
            guard case .dataLoadingFailed(let underlying)? = error as? ImagePipeline.Error else {
                return false
            }
            return (underlying as? URLError)?.code == .notConnectedToInternet
        }
    }

    @Test func bodyThatIsNotAnImageFailsToDecode() async {
        dataLoader.stub(url, with: .data(Data("<html>Oops</html>".utf8), mimeType: "text/html"))

        await #expect {
            _ = try await ImagePipeline.stubbed(dataLoader).image(for: url)
        } throws: { error in
            guard case .decodingFailed? = error as? ImagePipeline.Error else {
                return false
            }
            return "\(error)".contains("text/html")
        }
    }

    @Test func hangingRequestCanBeCancelled() async {
        dataLoader.stub(url, with: .hanging)
        let task = ImagePipeline.stubbed(dataLoader).imageTask(with: url)

        task.cancel()

        await #expect {
            _ = try await task.response
        } throws: { error in
            (error as? ImagePipeline.Error)?.isCancelled == true
        }
    }

    @Test func configurationCanBeChanged() {
        let pipeline = ImagePipeline.stubbed(dataLoader) {
            $0.isDiagnosticsEnabled = true
        }

        #expect(pipeline.configuration.isDiagnosticsEnabled)
        #expect(pipeline.configuration.dataCache == nil)
        #expect(pipeline.configuration.imageCache == nil)
    }
}
