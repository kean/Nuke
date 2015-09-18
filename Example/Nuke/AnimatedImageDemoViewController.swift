//
//  AnimatedImageDemoViewController.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 18/09/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import UIKit
import UIKit
import Nuke

private let textViewCellReuseID = "textViewReuseID"
private let imageCellReuseID = "imageCellReuseID"

class AnimatedImageDemoViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    var imageURLs = [NSURL]()
    var previousImageManager: ImageManaging!
    
    deinit {
        ImageManager.setShared(self.previousImageManager)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Enable GIF
        self.previousImageManager = ImageManager.shared()
        
        let decoder = ImageDecoderComposition(decoders: [AnimatedImageDecoder(), ImageDecoder()])
        let configuration = ImageManagerConfiguration(dataLoader: ImageDataLoader(), decoder:decoder)
        ImageManager.setShared(ImageManager(configuration: configuration))
        
        self.collectionView?.registerClass(UICollectionViewCell.self, forCellWithReuseIdentifier: textViewCellReuseID)
        self.collectionView?.registerClass(AnimatedImageCell.self, forCellWithReuseIdentifier: imageCellReuseID)
        self.collectionView?.backgroundColor = UIColor.whiteColor()
        
        let layout = self.collectionViewLayout as! UICollectionViewFlowLayout
        layout.sectionInset = UIEdgeInsetsMake(8, 8, 8, 8);
        layout.minimumInteritemSpacing = 8;
        
        imageURLs = [
            NSURL(string: "https://cloud.githubusercontent.com/assets/1567433/6505557/77ff05ac-c2e7-11e4-9a09-ce5b7995cad0.gif")!,
            NSURL(string: "https://cloud.githubusercontent.com/assets/1567433/6505565/8aa02c90-c2e7-11e4-8127-71df010ca06d.gif")!,
            NSURL(string: "https://cloud.githubusercontent.com/assets/1567433/6505571/a28a6e2e-c2e7-11e4-8161-9f39cc3bb8df.gif")!,
            NSURL(string: "https://cloud.githubusercontent.com/assets/1567433/6505576/b785a8ac-c2e7-11e4-831a-666e2b064b95.gif")!,
            NSURL(string: "https://cloud.githubusercontent.com/assets/1567433/6505579/c88c77ca-c2e7-11e4-88ad-d98c7360602d.gif")!,
            NSURL(string: "https://cloud.githubusercontent.com/assets/1567433/6505595/def06c06-c2e7-11e4-9cdf-d37d28618af0.gif")!,
            NSURL(string: "https://cloud.githubusercontent.com/assets/1567433/6505634/26e5dad2-c2e8-11e4-89c3-3c3a63110ac0.gif")!,
            NSURL(string: "https://cloud.githubusercontent.com/assets/1567433/6505643/42eb3ee8-c2e8-11e4-8666-ac9c8e1dc9b5.gif")!
        ]
    }
    
    // MARK: Collection View
    
    override func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return 2
    }
    
    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return section == 0 ? 1 : self.imageURLs.count;
    }
    
    override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCellWithReuseIdentifier(textViewCellReuseID, forIndexPath: indexPath)
            var textView: UITextView! = cell.viewWithTag(14) as? UITextView
            if textView == nil {
                textView = UITextView()
                textView.textColor = UIColor.blackColor()
                textView.font = UIFont.systemFontOfSize(16)
                textView.editable = false;
                textView.textAlignment = .Center
                textView.dataDetectorTypes = .Link
                
                cell.contentView.addSubview(textView)
                textView.frame = cell.contentView.bounds;
                textView.autoresizingMask = [.FlexibleHeight, .FlexibleWidth]
                
                textView.text = "Images by Florian de Looij\n http://flrn.nl/gifs/"
            }
            return cell
        } else {
            let cell: AnimatedImageCell = collectionView.dequeueReusableCellWithReuseIdentifier(imageCellReuseID, forIndexPath: indexPath) as! AnimatedImageCell
            var request = ImageRequest(URL: self.imageURLs[indexPath.row])
            request.shouldDecompressImage = false
            cell.setImageWithRequest(request)
            return cell
        }
    }
    
    override func collectionView(collectionView: UICollectionView, didEndDisplayingCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        cell.prepareForReuse()
    }
    
    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        let width = self.view.bounds.size.width - layout.sectionInset.left - layout.sectionInset.right
        if indexPath.section == 0 {
            return CGSize(width: width, height: 50)
        } else {
            return CGSize(width: width, height: width)
        }
    }
}

private class AnimatedImageCell: UICollectionViewCell {
    private let imageView = AnimatedImageView(frame: CGRectZero)
    private let progressView = UIProgressView()
    private var currentProgress: NSProgress? {
        willSet (newProgress) {
            if let progress = self.currentProgress {
                progress.removeObserver(self, forKeyPath: "fractionCompleted", context: nil)
            }
            if let progress = newProgress {
                self.progressView.progress = Float(progress.fractionCompleted)
                progress.addObserver(self, forKeyPath: "fractionCompleted", options: [.New], context: nil)
            }
            
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1)
        
        self.addSubview(self.imageView)
        self.addSubview(self.progressView)
        
        self.imageView.translatesAutoresizingMaskIntoConstraints = false;
        self.progressView.translatesAutoresizingMaskIntoConstraints = false;
        
        let views = ["imageView": self.imageView, "progressView": self.progressView]
        
        self.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("|[imageView]|", options: NSLayoutFormatOptions(), metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|[imageView]|", options: NSLayoutFormatOptions(), metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("|[progressView]|", options: NSLayoutFormatOptions(), metrics: nil, views: views))
        self.addConstraints(NSLayoutConstraint.constraintsWithVisualFormat("V:|[progressView(==4)]", options: NSLayoutFormatOptions(), metrics: nil, views: views))
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    func setImageWithURL(URL: NSURL) {
        self.setImageWithRequest(ImageRequest(URL: URL))
    }
    
    func setImageWithRequest(request: ImageRequest) {
        self.imageView.setImageWithRequest(request)
        self.currentProgress = self.imageView.imageTask?.progress
        if self.imageView.imageTask?.state == .Completed {
            self.progressView.alpha = 0;
        }
    }
    
    private override func prepareForReuse() {
        super.prepareForReuse()
        self.progressView.progress = 0
        self.progressView.alpha = 1
        self.currentProgress = nil
        self.imageView.prepareForReuse()
    }
    
    private override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if let progress = self.currentProgress where object === progress {
            dispatch_async(dispatch_get_main_queue()) {
                self.progressView.setProgress(Float(progress.fractionCompleted), animated: true)
                if progress.fractionCompleted == 1 {
                    UIView.animateWithDuration(0.2) {
                        self.progressView.alpha = 0
                    }
                }
            }
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
}
