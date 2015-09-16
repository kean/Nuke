// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public class ImageView: UIImageView {
    public var imageTask: ImageTask?
    public var allowsAnimations = true
    
    public func prepareForReuse() {
        self.image = nil
        self.cancelFetching()
    }
    
    private func cancelFetching() {
        self.imageTask?.cancel()
        self.imageTask?.completionHandler = nil
        self.imageTask = nil
    }
    
    public func setImageWithURL(URL: NSURL) {
        self.setImageWithRequest(ImageRequest(URL: URL))
    }
    
    public func setImageWithRequest(request: ImageRequest) {
        self.cancelFetching()
        
        let task = ImageManager.shared().imageTaskWithRequest(request) { [weak self] in
            self?.imageTaskDidFinishWithResponse($0)
        }
        task.resume()
    }
    
    public func imageTaskDidFinishWithResponse(response: ImageResponse) {
        switch response {
        case let .Success(image, info):
            if self.allowsAnimations && !info.fastResponse && self.image == nil {
                self.image = image
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = 0.0
                animation.toValue = 0.0
                animation.duration = 0.25
                self.layer.addAnimation(animation, forKey: "opacity")
            } else {
                self.image = image
            }
        default: return
        }
    }
}
