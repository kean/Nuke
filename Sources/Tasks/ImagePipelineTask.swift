// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

class ImagePipelineTask<Value>: Task<Value, ImagePipeline.Error> {
    let pipeline: ImagePipeline
    let configuration: ImagePipeline.Configuration
    let request: ImageRequest

    init(_ pipeline: ImagePipeline, _ request: ImageRequest) {
        self.pipeline = pipeline
        self.configuration = pipeline.configuration
        self.request = request
    }
}
