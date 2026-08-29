// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Essentials/errors.md`.

import Foundation
import SwiftUI
import Nuke
import NukeUI

// MARK: - Overview

private struct TypedErrorView: View {
    let url: URL

    var body: some View {
        LazyImage(url: url) { state in
            if case .dataDownloadExceededMaximumSize = state.error {
                Text("Image too large")
            } else if let image = state.image {
                image.resizable()
            }
        }
    }
}

// MARK: - Unwrapping the Underlying Error

private func message(for error: ImagePipeline.Error) -> String? {
    guard !error.isCancelled else { return nil }
    switch error.dataLoadingError {
    case let urlError as URLError where urlError.code == .notConnectedToInternet:
        return "You're offline"
    case let loaderError as DataLoader.Error:
        if case let .statusCodeUnacceptable(statusCode) = loaderError {
            return "Server returned \(statusCode)"
        }
        return "Couldn't load the image"
    default:
        return "Couldn't load the image"
    }
}

#if canImport(UIKit) && !os(watchOS)

import UIKit
import os

@MainActor
private final class ErrorsSnippets {
    let url = URL(string: "https://example.com/image")!
    let imageView = UIImageView()
    let logger = Logger()

    // MARK: - Overview

    func typedCatch() async {
        do {
            imageView.image = try await ImagePipeline.shared.image(for: url)
        } catch {
            // `error` is an `ImagePipeline.Error` – no cast, no `as?`
            switch error {
            case .dataDownloadExceededMaximumSize:
                showTooLargeMessage()
            default:
                showFailureImage()
            }
        }
    }

    // MARK: - Cancellation Is Not a Failure

    func filteringCancellation() async {
        do {
            imageView.image = try await ImagePipeline.shared.image(for: url)
        } catch {
            guard !error.isCancelled else { return }
            logger.error("Failed to load image: \(error)")
        }
    }

    private func showTooLargeMessage() {}
    private func showFailureImage() {}
}

#endif
