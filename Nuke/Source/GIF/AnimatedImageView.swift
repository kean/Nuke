// The MIT License (MIT)
//
// Copyright (c) 2015 Alexander Grebenyuk (github.com/kean).

import UIKit
import FLAnimatedImage

public class AnimatedImageView: ImageView {
    public let animatedImageView: FLAnimatedImageView
    public var allowsAnimatedImagePlayback = true
    
    public override init(frame: CGRect) {
        self.animatedImageView = FLAnimatedImageView()
        super.init(frame: frame)
        self.commonInit()
    }
    
    public convenience init() {
        self.init(frame: CGRectZero)
    }
    
    public required init?(coder decoder: NSCoder) {
        self.animatedImageView = FLAnimatedImageView()
        super.init(coder: decoder)
        self.commonInit()
    }
    
    func commonInit() {
        self.addSubview(animatedImageView)
        self.animatedImageView.frame = self.bounds
        self.animatedImageView.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
        self.animatedImageView.contentMode = .ScaleAspectFill
        self.animatedImageView.clipsToBounds = true
    }
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        self.animatedImageView.animatedImage = nil
    }
    
    public override func imageTaskDidFinishWithResponse(response: ImageResponse) {
        switch response {
        case let .Success(image, info):
            if self.allowsAnimations && !info.fastResponse && self.image == nil {
                self.displayImage(image)
                self.alpha = 0.0
                UIView.animateWithDuration(0.25) {
                    self.alpha = 1.0
                }
            } else {
                self.displayImage(image)
            }
        default: return
        }
    }
    
    public func displayImage(image: UIImage?) {
        if let animatedImage = image as? AnimatedImage where self.allowsAnimatedImagePlayback {
            self.animatedImageView.animatedImage = animatedImage.animatedImage
        } else {
            self.animatedImageView.image = image
        }
    }
    
}
