// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke
import AVKit

private let textViewCellReuseID = "textViewReuseID"
private let imageCellReuseID = "imageCellReuseID"

final class AnimatedImageUsingVideoViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    private var imageURLs = [URL]()
    private let storage = try! TemporaryVideoStorage()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        MP4Decoder.register()

        imageURLs = [
            URL(string: "https://kean.github.io/videos/cat_video.mp4")!
        ]

        collectionView?.register(VideoCell.self, forCellWithReuseIdentifier: imageCellReuseID)
        collectionView?.backgroundColor = UIColor.white

        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        layout.minimumInteritemSpacing = 8
    }

    // MARK: Collection View

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageURLs.count
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: imageCellReuseID, for: indexPath) as! VideoCell
        cell.storage = storage

        // Do it once somewhere where you configure the app / pipelines.
        ImagePipeline.Configuration.isAnimatedImageDataEnabled = true

        cell.activityIndicator.startAnimating()
        loadImage(
            with: imageURLs[indexPath.row],
            into: cell,
            completion: { [weak cell] _ in
                cell?.activityIndicator.stopAnimating()
            }
        )

        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        let width = view.bounds.size.width - layout.sectionInset.left - layout.sectionInset.right
        return CGSize(width: width, height: width)
    }
}

// MARK: - MP4Decoder

final class MP4Decoder: ImageDecoding {
    func decode(data: Data, isFinal: Bool) -> Image? {
        guard isFinal else { return nil }

        let image = Image()
        image.animatedImageData = data
        image.mimeType = "video/mp4"
        return image
    }

    private static func _match(_ data: Data, offset: Int = 0, _ numbers: [UInt8]) -> Bool {
        guard data.count >= numbers.count + offset else { return false }
        return !zip(numbers.indices, numbers).contains { (index, number) in
            data[index + offset] != number
        }
    }

    private static var isRegistered: Bool = false

    static func register() {
        guard !isRegistered else { return }
        isRegistered = true
        ImageDecoderRegistry.shared.register {
            // FIXME: these magic numbers are for:
            // ftypisom - ISO Base Media file (MPEG-4) v1
            // There are a bunch of other ways to create MP4
            // https://www.garykessler.net/library/file_sigs.html
            guard _match($0.data, offset: 4, [0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D]) else {
                return nil
            }
            return MP4Decoder()
        }
    }
}

private var _imageFormatAK = "Nuke.ImageFormat.AssociatedKey"

private extension Image {
    // At some point going to be available in the main repo.
    var mimeType: String? {
        get { return objc_getAssociatedObject(self, &_imageFormatAK) as? String }
        set { objc_setAssociatedObject(self, &_imageFormatAK, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - VideoCell

/// - warning: This is proof of concept, please don't use in production.
private final class VideoCell: UICollectionViewCell, Nuke.Nuke_ImageDisplaying {
    private var requestId: Int = 0
    private var videoURL: URL?
    var storage: TemporaryVideoStorage!

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AnyObject?

    let activityIndicator: UIActivityIndicatorView

    deinit {
        prepareForReuse()
    }

    override init(frame: CGRect) {
        activityIndicator = UIActivityIndicatorView(style: .gray)

        super.init(frame: frame)

        self.backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1.0)

        contentView.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .centerX, relatedBy: .equal, toItem: contentView, attribute: .centerX, multiplier: 1.0, constant: 0.0))
        contentView.addConstraint(NSLayoutConstraint(item: activityIndicator, attribute: .centerY, relatedBy: .equal, toItem: contentView, attribute: .centerY, multiplier: 1.0, constant: 0.0))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        videoURL.map(storage.removeData(for:))
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
    }

    func nuke_display(image: Image?) {
        prepareForReuse()

        guard let data = image?.animatedImageData else {
            return
        }

        assert(image?.mimeType == "video/mp4")

        self.requestId += 1
        let requestId = self.requestId

        storage.storeData(data) { [weak self] url in
            guard self?.requestId == requestId else { return }
            self?._playVideoAtURL(url)
        }
    }

    private func _playVideoAtURL(_ url: URL) {
        let playerItem = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: playerItem)
        let playerLayer = AVPlayerLayer(player: player)
        self.playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)

        contentView.layer.addSublayer(playerLayer)
        playerLayer.frame = contentView.bounds

        player.play()

        self.player = player
        self.playerLayer = playerLayer
    }
}

// MARK: - TemporaryVideoStorage

/// AVPlayer doesn't support playing videos from Data, that's why we temporary
/// store it on disk.
private final class TemporaryVideoStorage {
    private let path: URL
    private let _queue = DispatchQueue(label: "com.github.kean.Nuke.TemporaryVideoStorage.Queue")

    init() throws {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError, userInfo: nil)
        }
        self.path = root.appendingPathComponent("com.github.kean.Nuke.TemporaryVideoStorage", isDirectory: true)
        // Clear the contents that could potentially was left from the previous session.
        try? FileManager.default.removeItem(at: path)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true, attributes: nil)
    }

    func storeData(_ data: Data, _ completion: @escaping (URL) -> Void) {
        _queue.async {
            let url = self.path.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            try? data.write(to: url) // Ignore that write may fail in some cases
            DispatchQueue.main.async {
                completion(url)
            }
        }
    }

    func removeData(for url: URL) {
        _queue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
