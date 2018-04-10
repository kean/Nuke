// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockTarget: Target {
    var handler: ((Result<Image>, _ isFromMemoryCache: Bool) -> Void)?
    
    func handle(response: Result<Image>, isFromMemoryCache: Bool) {
        handler?(response, isFromMemoryCache)
    }
}
