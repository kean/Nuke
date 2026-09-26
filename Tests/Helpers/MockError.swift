// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// An error for a test double to fail with, told apart by its description.
struct MockError: Error, Equatable {
    let description: String
}
