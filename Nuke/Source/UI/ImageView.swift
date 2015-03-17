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

public class ImageView: UIImageView {
    public var imageTask: ImageTask?
    public var allowsAnimations = true
    
    public func prepareForReuse() {
        self.image = nil
        self.imageTask?.cancel()
        self.imageTask = nil
    }
    
    public func setImageWithURL(URL: NSURL) {
        self.setImageWithRequest(ImageRequest(URL: URL))
    }
    
    public func setImageWithRequest(request: ImageRequest) {
        self.imageTask?.cancel()
        self.imageTask = nil
        
        let startTime = CACurrentMediaTime()
        let imageTask = ImageManager.sharedManager().imageTaskWithRequest(request, completionHandler: { [weak self] (response) -> Void in
            self?.imageTaskDidFinishWithImage(response.image, error: response.error, elapsedTime: (CACurrentMediaTime() - startTime))
            return
        })
        imageTask.resume()
    }
    
    private func imageTaskDidFinishWithImage(image: UIImage?, error: NSError?, elapsedTime: NSTimeInterval) {
        var isFastResponse = Int(elapsedTime) * 1000 < 32 // 32 ms
        if self.allowsAnimations && !isFastResponse && self.image == nil {
            self.image = image
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 0.0
            animation.toValue = 0.0
            animation.duration = 0.25
            self.layer.addAnimation(animation, forKey: "opacity")
        } else {
            self.image = image
        }
    }
}
