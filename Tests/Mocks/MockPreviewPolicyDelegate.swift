// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation
import os
import Nuke

/// Returns the given preview policies in order, then keeps returning the last
/// one, and counts how many times the pipeline asked for one.
final class MockPreviewPolicyDelegate: ImagePipeline.Delegate, Sendable {
    var policyRequestCount: Int { _policyRequestCount.withLock { $0 } }

    private let policies: [ImagePipeline.PreviewPolicy]
    private let _policyRequestCount = OSAllocatedUnfairLock(initialState: 0)

    init(policies: [ImagePipeline.PreviewPolicy]) {
        precondition(!policies.isEmpty)
        self.policies = policies
    }

    /// Returns the same policy for every request.
    convenience init(policy: ImagePipeline.PreviewPolicy) {
        self.init(policies: [policy])
    }

    func previewPolicy(for context: ImageDecodingContext, pipeline: ImagePipeline) -> ImagePipeline.PreviewPolicy {
        let index = _policyRequestCount.withLock { count in
            defer { count += 1 }
            return min(count, policies.count - 1)
        }
        return policies[index]
    }
}
