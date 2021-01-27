// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

// Each task holds a strong reference to the pipeline. This is by design. The
// user does not need to hold a strong reference to the pipeline.
class ImagePipelineTask<Value>: Task<Value, ImagePipeline.Error> {
    let pipeline: ImagePipeline
    let request: ImageRequest
    let log: OSLog
    private let queue: DispatchQueue

    init(_ pipeline: ImagePipeline, _ request: ImageRequest, _ queue: DispatchQueue, _ log: OSLog) {
        self.pipeline = pipeline
        self.request = request
        self.queue = queue
        self.log = log
    }

    /// Executes work on the pipeline synchronization queue.
    func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }
}
