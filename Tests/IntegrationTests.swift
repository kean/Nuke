// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import XCTest
import Nuke

class IntegrationTests: XCTestCase {
    var deduplicator: Loading!

    override func setUp() {
        super.setUp()
        
        let loader = Loader(loader: MockDataLoader(), decoder: DataDecoder(), cache: nil)
        deduplicator = Deduplicator(loader: loader)
    }

    // MARK: Thread-Safety
    
    func testThreadSafety() {
        runThreadSafetyTests(for: deduplicator)
    }
}
