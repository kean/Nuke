// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

// Each task holds a strong reference to the pipeline. This is by design. The
// user does not need to hold a strong reference to the pipeline.
class ImagePipelineTask<Value>: AsyncTask<Value, ImagePipeline.Error> {
    let pipeline: ImagePipeline
    // A canonical request representing the unit work performed by the task.
    let request: ImageRequest

    init(_ pipeline: ImagePipeline, _ request: ImageRequest) {
        self.pipeline = pipeline
        self.request = request
    }
}

// Returns all image tasks subscribed to the current pipeline task.
// A suboptimal approach just to make the new DiskCachPolicy.automatic work.
protocol ImageTaskSubscribers {
    var imageTasks: [ImageTask] { get }
}

extension ImageTask: ImageTaskSubscribers {
    var imageTasks: [ImageTask] {
        [self]
    }
}

extension ImagePipelineTask: ImageTaskSubscribers {
    var imageTasks: [ImageTask] {
        subscribers.flatMap { subscribers -> [ImageTask] in
            (subscribers as? ImageTaskSubscribers)?.imageTasks ?? []
        }
    }
}
