// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke
@testable import NukeUI

// BUG: `FetchImage.priority` is documented as
//
//     /// Overrides the priority of the current and future requests. When `nil`
//     /// (the default), the request's own priority is used. Can be updated while
//     /// a task is already running.
//
// but its `didSet` (Sources/NukeUI/FetchImage.swift:65-71) only forwards
// non-nil values to the running task. Setting it back to `nil` leaves the
// running task at the overridden priority.
//
// This is exactly the pattern the FetchImage docs recommend for off-screen
// images (lower the priority in `onDisappear`, undo it in `onAppear`), and
// `LazyImage.onAppear` only gets away with it because it restarts the request
// right after (`viewModel.priority = nil; viewModel.load(...)`).
//
// Expected: after `priority = nil`, the running task uses the request's own
// priority (`.high` here).
// Actual: the task stays at `.veryLow`.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct FetchImagePriorityResetBugRepro {
    @Test func settingPriorityBackToNilRestoresTheRequestPriority() async throws {
        let dataLoader = MockDataLoader()
        dataLoader.isSuspended = true
        let image = FetchImage()
        image.pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
        }
        let task = Ref<ImageTask?>(nil)
        image.onStart = { task.value = $0 }

        image.load(ImageRequest(url: Test.url, priority: .high))
        let imageTask = try #require(task.value)
        #expect(imageTask.priority == .high)

        image.priority = .veryLow
        #expect(imageTask.priority == .veryLow)

        image.priority = nil

        // Expected: .high. Actual: .veryLow.
        #expect(imageTask.priority == .high)
    }
}
