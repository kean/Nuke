// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockTarget: ImageTarget {
    var handler: ((_ response: ImageResponse?, _ error: Error?, _ isFromMemoryCache: Bool) -> Void)?

    func handle(response: ImageResponse?, error: Error?, isFromMemoryCache: Bool) {
        handler?(response, error, isFromMemoryCache)
    }
}
