// The MIT License (MIT)
//
// Copyright (c) 2015-2020 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke
import AVKit

// MARK: - AnimatedImageUsingVideoViewController

final class AnimatedImageUsingVideoViewController: UICollectionViewController, UICollectionViewDelegateFlowLayout {
    override init(nibName nibNameOrNil: String? = nil, bundle nibBundleOrNil: Bundle? = nil) {
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(collectionViewLayout: UICollectionViewFlowLayout())
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        TemporaryVideoStorage.shared.removeAll()
        ImageDecoders.MP4.register()

        collectionView?.register(VideoCell.self, forCellWithReuseIdentifier: imageCellReuseID)
        if #available(iOS 13.0, *) {
            collectionView.backgroundColor = UIColor.systemBackground
        } else {
            collectionView.backgroundColor = UIColor.white
        }

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
        cell.setVideo(with: imageURLs[indexPath.row])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let layout = collectionViewLayout as! UICollectionViewFlowLayout
        let width = view.bounds.size.width - layout.sectionInset.left - layout.sectionInset.right
        return CGSize(width: width, height: width)
    }
}

private let imageCellReuseID = "imageCellReuseID"

private let imageURLs = [
    URL(string: "https://kean.github.io/videos/cat_video.mp4")!
]

// MARK: - MP4Decoder

private extension ImageDecoders {
    final class MP4: ImageDecoding {
        func decode(_ data: Data) -> ImageContainer? {
            var container = ImageContainer(image: UIImage())
            container.data = data
            container.userInfo["mime-type"] = "video/mp4"
            return container
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
                return MP4()
            }
        }
    }
}

// MARK: - VideoCell

/// - warning: This is proof of concept, please don't use in production.
private final class VideoCell: UICollectionViewCell {
    private var requestId: Int = 0
    private var videoURL: URL?
    private var task: ImageTask?

    private let spinner: UIActivityIndicatorView
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var playerLooper: AnyObject?

    deinit {
        prepareForReuse()
    }

    override init(frame: CGRect) {
        spinner = UIActivityIndicatorView(style: .gray)

        super.init(frame: frame)

        backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1.0)

        contentView.addSubview(spinner)
        spinner.centerInSuperview()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        videoURL.map(TemporaryVideoStorage.shared.removeData(for:))
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        player = nil
    }

    func setVideo(with url: URL) {
        let pipeline = ImagePipeline.shared
        let request = ImageRequest(url: url)

        if let image = pipeline.cachedImage(for: request) {
            return display(image)
        }

        spinner.startAnimating()
        task = pipeline.loadImage(with: request) { [weak self] result in
            self?.spinner.stopAnimating()
            if case let .success(response) = result {
                self?.display(response.container)
            }
        }
    }

    private func display(_ container: ImageContainer) {
        guard let data = container.data else {
            return
        }

        assert(container.userInfo["mime-type"] as? String == "video/mp4")

        self.requestId += 1
        let requestId = self.requestId

        TemporaryVideoStorage.shared.storeData(data) { [weak self] url in
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

    // Ignoring error handling for simplicity.
    static let shared = try! TemporaryVideoStorage()

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

    func removeAll() {
        _queue.async {
            // Clear the contents that could potentially was left from the previous session.
            try? FileManager.default.removeItem(at: self.path)
            try? FileManager.default.createDirectory(at: self.path, withIntermediateDirectories: true, attributes: nil)
        }
    }
}
