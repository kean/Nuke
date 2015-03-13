// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation
import Photos

public enum ImageContentMode {
    case AspectFill
    case AspectFit
}

public class ImageManager {
    func requestImage(URL: NSURL, completionHandler: (ImageResponse)) -> ImageTask {
        return ImageTask()
    }
    
    func requestImage(URL: NSURL, targetSize: CGSize, contentMode: ImageContentMode, options: ImageRequestOptions, completionHandler: (ImageResponse)) -> ImageTask {
        return ImageTask()
    }
    
    func requestImage(request: ImageRequest, completionHandler: (ImageResponse)) -> ImageTask {
        return ImageTask()
    }
    
    func startPreheatingImages(requests: [ImageRequest]) {
        
    }
    
    func stopPreheatingImages(request: [ImageRequest]) {
        
    }
    
    func stopPreheatingImages() {
        
    }
}
