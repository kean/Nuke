// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Customization/LoadingData/retrying-requests.md`.

import Foundation
import SwiftUI
import NukeUI

private func enableRetries() {
    ImagePipeline.shared = ImagePipeline {
        $0.retryPolicy = .default
    }
}

private func changePolicy() {
    var policy = ImagePipeline.RetryPolicy.default
    policy.maxRetryCount = 4
    policy.backoff = .exponential(initial: 1, multiplier: 3)
    policy.retryableStatusCodes.insert(404) // A CDN that takes a moment to catch up

    let pipeline = ImagePipeline {
        $0.retryPolicy = policy
    }
    _ = pipeline
}

private func retryASingleRequest(heroURL: URL, thumbnailURL: URL) {
    var hero = ImageRequest(url: heroURL)
    hero.retryPolicy = ImagePipeline.RetryPolicy(maxRetryCount: 5)

    var thumbnail = ImageRequest(url: thumbnailURL)
    thumbnail.retryPolicy = .disabled

    _ = (hero, thumbnail)
}

private actor TokenStore {
    static let shared = TokenStore()

    var token = ""

    func refresh() async {}
}

private final class AuthenticatedPipelineDelegate: Sendable {}

extension AuthenticatedPipelineDelegate: ImagePipeline.Delegate {
    func willLoadData(for request: ImageRequest, urlRequest: URLRequest, pipeline: ImagePipeline) async throws -> URLRequest {
        var urlRequest = urlRequest
        urlRequest.setValue("Bearer \(await TokenStore.shared.token)", forHTTPHeaderField: "Authorization")
        return urlRequest
    }

    func retryDecision(for context: ImagePipeline.RetryContext, pipeline: ImagePipeline) async -> ImagePipeline.RetryDecision {
        if context.statusCode == 401, context.retryCount == 0 {
            await TokenStore.shared.refresh()
            return .retry(after: 0)
        }
        return context.policy?.decision(for: context) ?? .stop
    }
}

private struct RetryButtonView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else if state.error != nil {
                Button("Try Again") { state.reload() }
            } else {
                ProgressView()
            }
        }
    }
}
