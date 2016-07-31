// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

extension XCTestCase {
    func runThreadSafetyTests(for loader: Loading) {
        for _ in 0..<250 {
            self.expect { fulfill in
                let request = Request(url: URL(string: "\(defaultURL)/\(arc4random_uniform(10))")!)
                let shouldCancel = arc4random_uniform(3) == 0
                
                let cts = CancellationTokenSource()
                _ = loader.loadImage(with: request, token: cts.token).then { _ in
                    if shouldCancel {
                        // do nothing, we don't expect completion on cancel
                    } else {
                        fulfill()
                    }
                }
                
                if shouldCancel {
                    cts.cancel()
                    fulfill()
                }
            }
        }
        wait()
    }
}
