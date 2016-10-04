// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

extension XCTestCase {
    func runThreadSafetyTests(for loader: Loading) {
        for _ in 0..<500 {
            expect { fulfill in
                DispatchQueue.global().async {
                    let request = Request(url: URL(string: "\(defaultURL)/\(rnd(10))")!)
                    let shouldCancel = rnd(3) == 0
                    
                    let cts = CancellationTokenSource()
                    // Dispatch on global queue to avoid waiting on main thread
                    _ = loader.loadImage(with: request, token: cts.token).then(on: DispatchQueue.global()) { _ in
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
        }
        wait(10)
    }
}
