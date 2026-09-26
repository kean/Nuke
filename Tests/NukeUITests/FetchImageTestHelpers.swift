// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import NukeUI

extension FetchImage {
    /// Loads the image and waits for ``FetchImage/onCompletion``, which it
    /// replaces for the duration of the load.
    ///
    /// - returns: The result the completion was called with, or `nil` if it
    ///   wasn't called in time, which records an issue.
    @discardableResult
    func loadAndWait(_ request: ImageRequest?) async -> Result<ImageResponse, ImagePipeline.Error>? {
        await waitForCompletion { load(request) }
    }

    /// Loads the image and waits for ``FetchImage/onCompletion``, which it
    /// replaces for the duration of the load.
    @discardableResult
    func loadAndWait(_ url: URL?) async -> Result<ImageResponse, ImagePipeline.Error>? {
        await waitForCompletion { load(url) }
    }

    /// Loads the image with the given action and waits for
    /// ``FetchImage/onCompletion``, which it replaces for the duration of the
    /// load.
    @discardableResult
    func loadAndWait(_ action: @escaping () async throws -> ImageResponse) async -> Result<ImageResponse, ImagePipeline.Error>? {
        await waitForCompletion { load(action) }
    }

    private func waitForCompletion(of load: () -> Void) async -> Result<ImageResponse, ImagePipeline.Error>? {
        let completed = TestExpectation()
        let result = Ref<Result<ImageResponse, ImagePipeline.Error>?>(nil)
        let onCompletion = self.onCompletion
        self.onCompletion = {
            result.value = $0
            completed.fulfill()
        }
        load()
        await completed.wait()
        self.onCompletion = onCompletion
        return result.value
    }
}
