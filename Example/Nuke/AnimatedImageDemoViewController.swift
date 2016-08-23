// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke
import NukeAnimatedImagePlugin
import FLAnimatedImage

private let textViewCellReuseID = "textViewReuseID"
private let imageCellReuseID = "imageCellReuseID"

class AnimatedImageDemoViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    var imageURLs = [URL]()
    
    let manager: Nuke.Manager = {
        let decoder = NukeAnimatedImagePlugin.DataDecoderComposition(decoders: [AnimatedImageDecoder(), Nuke.DataDecoder()])
        let cache = Nuke.Cache().preparedForAnimatedImages()
        let loader = Nuke.Loader(loader: Nuke.DataLoader(), decoder: decoder, cache: cache)
        return Manager(loader: loader, cache: cache)
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        collectionView?.register(UICollectionViewCell.self, forCellWithReuseIdentifier: textViewCellReuseID)
        collectionView?.register(UICollectionViewCell.self, forCellWithReuseIdentifier: imageCellReuseID)
        collectionView?.backgroundColor = UIColor.white

        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        layout.sectionInset = UIEdgeInsetsMake(8, 8, 8, 8)
        layout.minimumInteritemSpacing = 8
        
        let root = "https://cloud.githubusercontent.com/assets"
        imageURLs = [
            URL(string: "\(root)/1567433/6505557/77ff05ac-c2e7-11e4-9a09-ce5b7995cad0.gif")!,
            URL(string: "\(root)/1567433/6505565/8aa02c90-c2e7-11e4-8127-71df010ca06d.gif")!,
            URL(string: "\(root)/1567433/6505571/a28a6e2e-c2e7-11e4-8161-9f39cc3bb8df.gif")!,
            URL(string: "\(root)/1567433/6505576/b785a8ac-c2e7-11e4-831a-666e2b064b95.gif")!,
            URL(string: "\(root)/1567433/6505579/c88c77ca-c2e7-11e4-88ad-d98c7360602d.gif")!,
            URL(string: "\(root)/1567433/6505595/def06c06-c2e7-11e4-9cdf-d37d28618af0.gif")!,
            URL(string: "\(root)/1567433/6505634/26e5dad2-c2e8-11e4-89c3-3c3a63110ac0.gif")!,
            URL(string: "\(root)/1567433/6505643/42eb3ee8-c2e8-11e4-8666-ac9c8e1dc9b5.gif")!
        ]
    }
    
    // MARK: Collection View
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return section == 0 ? 1 : imageURLs.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: textViewCellReuseID, for: indexPath)
            var textView: UITextView! = cell.viewWithTag(14) as? UITextView
            if textView == nil {
                textView = UITextView()
                textView.textColor = UIColor.black
                textView.font = UIFont.systemFont(ofSize: 16)
                textView.isEditable = false
                textView.textAlignment = .center
                textView.dataDetectorTypes = .link
                
                cell.contentView.addSubview(textView)
                textView.frame = cell.contentView.bounds
                textView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
                
                textView.text = "Images by Florian de Looij\n http://flrn.nl/gifs/"
            }
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: imageCellReuseID, for: indexPath)
            
            cell.backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1.0)
            
            let imageView = imageViewForCell(cell)
            imageView.image = nil
            manager.loadImage(with: Request(url: imageURLs[indexPath.row]), into: imageView) { response, isFromMemoryCache in
                switch response {
                case let .fulfilled(image):
                    imageView.nk_display(image)
                    if !isFromMemoryCache {
                        let animation = CABasicAnimation(keyPath: "opacity")
                        animation.duration = 0.25
                        animation.fromValue = 0
                        animation.toValue = 1
                        let layer: CALayer? = imageView.layer // Make compiler happy on OSX
                        layer?.add(animation, forKey: "imageTransition")
                    }
                case .rejected(_): return
                }
            }
            
            return cell
        }
    }
    
    func imageViewForCell(_ cell: UICollectionViewCell) -> FLAnimatedImageView {
        var imageView: FLAnimatedImageView! = cell.viewWithTag(15) as? FLAnimatedImageView
        if imageView == nil {
            imageView = FLAnimatedImageView(frame: cell.bounds)
            imageView.autoresizingMask =  [.flexibleWidth, .flexibleHeight]
            imageView.tag = 15
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            cell.addSubview(imageView!)
        }
        return imageView!
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        let width = view.bounds.size.width - layout.sectionInset.left - layout.sectionInset.right
        if indexPath.section == 0 {
            return CGSize(width: width, height: 50)
        } else {
            return CGSize(width: width, height: width)
        }
    }
}
