// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class MockImageTaskDelegate: ImageTaskDelegate {
    var _completion: ImageTask.Completion = { _ in }
    func imageTask(_ task: ImageTask, didFinishWithResult result: Result<Image>) {
        _completion(result)
    }

    var _progress: (Int64, Int64) -> Void = { _,_ in }
    func imageTask(_ task: ImageTask, didUpdateCompletedUnitCount completed: Int64, totalUnitCount total: Int64) {
        _progress(completed, total)
    }
}
