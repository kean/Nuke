// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

// Each task holds a strong reference to the pipeline. This is by design. The
// user does not need to hold a strong reference to the pipeline.
class ImagePipelineTask<Value>: Task<Value, ImagePipeline.Error> {
    let pipeline: ImagePipeline
    let request: ImageRequest

    init(_ pipeline: ImagePipeline, _ request: ImageRequest) {
        self.pipeline = pipeline
        self.request = request
    }

    /// Executes work on the pipeline synchronization queue.
    func async(_ work: @escaping () -> Void) {
        pipeline.queue.async(execute: work)
    }
}
