// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

extension XCTestCase {
    func runThreadSafetyTests(for pipeline: ImagePipeline) {
        for _ in 0..<500 {
            expect { fulfill in
                DispatchQueue.global().async {
                    let request = ImageRequest(url: URL(string: "\(defaultURL)/\(rnd(30))")!)
                    let shouldCancel = rnd(3) == 0

                    let task = pipeline.loadImage(with: request) { _,_ in
                        if shouldCancel {
                            // do nothing, we don't expect completion on cancel
                        } else {
                            fulfill()
                        }
                    }
                    
                    if shouldCancel {
                        task.cancel()
                        fulfill()
                    }
                }
            }
        }
        wait(10)
    }
}
