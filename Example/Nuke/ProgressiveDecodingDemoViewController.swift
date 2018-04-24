// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

final class ProgressiveDecodingDemoViewController: UIViewController {
    private let urls = [
        URL(string: "_mock_loader://progressive")!,
        URL(string: "_mock_loader://baseline")!,
    ]

    private let pipeline = ImagePipeline {
        $0.dataLoader = _MockDataLoader()
        $0.imageCache = nil
        $0.isDeduplicationEnabled = false
        $0.isProgressiveDecodingEnabled = true

        $0.imageProcessor = { _ in

            // Uncomment to enable progressive blur:

//            guard !$0.isFinal else {
//                return nil // No processing.
//            }
//
//            guard let scanNumber = $0.scanNumber else {
//                return nil
//            }
//
//            // Blur partial images.
//            if scanNumber < 5 {
//                // Progressively reduce blur as we load more scans.
//                let radius = max(2, 14 - scanNumber * 4)
//                let blur = GaussianBlur(radius: radius)
//                return AnyImageProcessor(blur)
//            }

            // Scans 5+ are already good enough not to blur them.
            return nil
        }
    }

    private var task: ImageTask?

    private let segmentedControl = UISegmentedControl(items: ["Progressive", "Baseline"])

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.white

        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(_segmentedControlValueChanged(_:)), for: .valueChanged)

        self.navigationItem.titleView = segmentedControl

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(_refresh))


        _start(with: urls[0])
    }

    private func _start(with url: URL) {
        self.title = segmentedControl.selectedSegmentIndex == 0 ? "Progressive JPEG" : "Baseline JPEG"

        view.viewWithTag(12)?.removeFromSuperview()

        let imageView = ProgressiveImageView()
        imageView.tag = 12

        view.addSubview(imageView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(
            [imageView.topAnchor.constraint(equalTo: view.topAnchor),
             imageView.leftAnchor.constraint(equalTo: view.leftAnchor),
             imageView.rightAnchor.constraint(equalTo: view.rightAnchor)]
        )

        self.task?.cancel()

        let task = pipeline.loadImage(with: url) {
            imageView.imageView.image = $0.value
        }

        task.progressHandler = {
            let text = NSMutableAttributedString(string: "")
            text.append(NSAttributedString(
                string: "Downloaded: ",
                attributes: [.font: UIFont.boldSystemFont(ofSize: 18)]
            ))
            let completed = ByteCountFormatter.string(fromByteCount: $0, countStyle: .binary)
            let total = ByteCountFormatter.string(fromByteCount: $1, countStyle: .binary)
            text.append(NSAttributedString(
                string: "\(completed) / \(total)",
                attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular)]
            ))
            imageView.labelProgress.attributedText = text
        }

        task.progressiveImageHandler = { image in
            UIView.transition(with: imageView,
                              duration: 0.25,
                              options: .transitionCrossDissolve,
                              animations: { imageView.imageView.image = image },
                              completion: nil)
        }

        self.task = task
    }

    @objc func _segmentedControlValueChanged(_ segmentedControl: UISegmentedControl) {
        _start(with: urls[segmentedControl.selectedSegmentIndex])
    }

    @objc func _refresh() {
        _start(with: urls[segmentedControl.selectedSegmentIndex])
    }
}

private final class ProgressiveImageView: UIView {
    let imageView = UIImageView()
    let labelProgress = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        _createUI()

        imageView.contentMode = .scaleAspectFill
        imageView.backgroundColor = UIColor.gray.withAlphaComponent(0.15)
        imageView.clipsToBounds = true

        labelProgress.text = ""
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func _createUI() {
        let labels = UIStackView(arrangedSubviews: [labelProgress])
        labels.axis = .vertical
        labels.spacing = 15
        labels.isLayoutMarginsRelativeArrangement = true
        labels.layoutMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)

        let stack = UIStackView(arrangedSubviews: [imageView, labels])
        stack.axis = .vertical
        stack.spacing = 0
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 15, left: 0, bottom: 15, right: 0)

        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.pinToSuperview()

        imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: 4.0 / 3.0).isActive = true
    }
}

private final class _MockDataLoader: DataLoading {
    private final class _MockTask: Cancellable {
        func cancel() { }
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        let data = _data(for: request)
        let chunks = _createChunks(for: data, size: 10240)
        let response = URLResponse(url: request.url!, mimeType: "image/jpeg", expectedContentLength: data.count, textEncodingName: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            self?._sendData(chunks, didReceiveData: { didReceiveData($0, response) }, completion: completion)
        }
        return _MockTask()
    }

    private func _sendData(_ data: [Data], didReceiveData: @escaping (Data) -> Void, completion: @escaping (Error?) -> Void) {
        guard !data.isEmpty else {
            completion(nil)
            return
        }
        let (x, xs) = (data[0], Array(data.dropFirst()))
        didReceiveData(x)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(75)) { [weak self] in
            self?._sendData(xs, didReceiveData: didReceiveData, completion: completion)
        }
    }

    private func _data(for request: URLRequest) -> Data {
        let url = Bundle.main.url(forResource: request.url!.lastPathComponent, withExtension: "jpeg")!
        return try! Data(contentsOf: url)
    }
}

private func _createChunks(for data: Data, size: Int) -> [Data] {
    var chunks = [Data]()
    let totalSize = data.count
    var offset = 0
    while offset < totalSize {
        let chunkSize = offset + size > totalSize ? totalSize - offset : size
        let chunk = data[offset..<(offset + chunkSize)]
        offset += chunkSize
        chunks.append(chunk)
    }
    return chunks
}
