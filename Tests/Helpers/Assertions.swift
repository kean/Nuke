// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing

/// Expects the values to be equal and to have the same hash.
func assertHashableEqual<T: Hashable>(_ lhs: T, _ rhs: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(lhs.hashValue == rhs.hashValue, sourceLocation: sourceLocation)
    #expect(lhs == rhs, sourceLocation: sourceLocation)
}
