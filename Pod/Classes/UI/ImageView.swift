// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import Foundation

public class ImageView: UIImageView {
    public var imageTask: ImageTask?
    public var allowsAnimations = true
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        self.contentMode = .ScaleAspectFill
        self.clipsToBounds = true
    }
    
    public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
    }
    
    public func prepareForReuse() {
        self.image = nil
        self.cancelFetching()
    }
    
    private func cancelFetching() {
        self.imageTask?.completion = nil
        self.imageTask?.cancel()
        self.imageTask = nil
    }
    
    public func setImageWithURL(URL: NSURL) {
        self.setImageWithRequest(ImageRequest(URL: URL, targetSize: self.targetSize(), contentMode: .AspectFill))
    }
    
    private func targetSize() -> CGSize {
        let size = self.bounds.size
        let scale = UIScreen.mainScreen().scale
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    
    public func setImageWithRequest(request: ImageRequest) {
        self.cancelFetching()
        self.imageTask = ImageManager.shared().taskWithRequest(request) { [weak self] in
            self?.imageTaskDidFinishWithResponse($0)
        }
        self.imageTask?.resume()
    }
    
    public func imageTaskDidFinishWithResponse(response: ImageResponse) {
        switch response {
        case let .Success(image, info):
            if self.allowsAnimations && !info.fastResponse && self.image == nil {
                self.image = image
                self.alpha = 0.0
                UIView.animateWithDuration(0.25) {
                    self.alpha = 1.0
                }
            } else {
                self.image = image
            }
        default: return
        }
    }
}
