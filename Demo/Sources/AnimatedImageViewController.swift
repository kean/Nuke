// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke
import FLAnimatedImage

private let textViewCellReuseID = "textViewReuseID"
private let imageCellReuseID = "imageCellReuseID"

final class AnimatedImageViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    private var imageURLs = [URL]()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView?.register(UICollectionViewCell.self, forCellWithReuseIdentifier: textViewCellReuseID)
        collectionView?.register(AnimatedImageCell.self, forCellWithReuseIdentifier: imageCellReuseID)
        collectionView?.backgroundColor = UIColor.white

        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
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

                textView.text = "Images by Florian de Looij\n http://flrngif.tumblr.com"
            }
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: imageCellReuseID, for: indexPath) as! AnimatedImageCell

            // Do it once somewhere where you configure the app / pipelines.
            ImagePipeline.Configuration.isAnimatedImageDataEnabled = true

            cell.activityIndicator.startAnimating()
            loadImage(
                with: imageURLs[indexPath.row],
                options: ImageLoadingOptions(transition: .fadeIn(duration: 0.33)),
                into: cell.imageView,
                completion: { [weak cell] _ in
                    cell?.activityIndicator.stopAnimating()
                }
            )

            return cell
        }
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

final class AnimatedImageCell: UICollectionViewCell {
    let imageView: FLAnimatedImageView
    let activityIndicator: UIActivityIndicatorView

    override init(frame: CGRect) {
        imageView = FLAnimatedImageView()
        activityIndicator = UIActivityIndicatorView(style: .gray)

        super.init(frame: frame)

        self.backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1.0)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true

        contentView.addSubview(imageView)
        imageView.frame = contentView.bounds
        imageView.autoresizingMask =  [.flexibleWidth, .flexibleHeight]

        contentView.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .centerX, relatedBy: .equal, toItem: contentView, attribute: .centerX, multiplier: 1.0, constant: 0.0))
        contentView.addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .centerY, relatedBy: .equal, toItem: contentView, attribute: .centerY, multiplier: 1.0, constant: 0.0))
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.nuke_display(image: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }
}

extension FLAnimatedImageView {
    @objc open override func nuke_display(image: Image?) {
        guard image != nil else {
            self.animatedImage = nil
            self.image = nil
            return
        }
        if let data = image?.animatedImageData {
            // Display poster image immediately
            self.image = image

            // Prepare FLAnimatedImage object asynchronously (it takes a
            // noticeable amount of time), and start playback.
            DispatchQueue.global().async {
                let animatedImage = FLAnimatedImage(animatedGIFData: data)
                DispatchQueue.main.async {
                    // If view is still displaying the same image
                    if self.image === image {
                        self.animatedImage = animatedImage
                    }
                }
            }
        } else {
            self.image = image
        }
    }
}
