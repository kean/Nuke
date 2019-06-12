// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

final class ProgressiveDecodingDemoViewController: UIViewController {
    private let urls = [
        URL(string: "_mock_loader://progressive")!,
        URL(string: "_mock_loader://baseline")!
    ]

    private let pipeline = ImagePipeline {
        $0.dataLoader = _MockDataLoader()
        $0.imageCache = nil
        $0.isDeduplicationEnabled = false
        $0.isProgressiveDecodingEnabled = true
    }

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

        let container = ProgressiveImageView()
        container.tag = 12

        view.addSubview(container)

        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(
            [container.topAnchor.constraint(equalTo: view.topAnchor),
             container.leftAnchor.constraint(equalTo: view.leftAnchor),
             container.rightAnchor.constraint(equalTo: view.rightAnchor)]
        )

        let imageView = container.imageView

        var options = ImageLoadingOptions()
        // Use our custom pipeline with progressive decoding enabled and
        // _MockDataLoader which returns data on predifined intervals.
        options.pipeline = pipeline
        options.transition = .fadeIn(duration: 0.25)

        loadImage(
            with: ImageRequest(url: url, processors: [_ProgressiveBlurImageProcessor()]),
            options: options,
            into: imageView,
            progress: { _, completed, total in
                container.updateProgress(completed: completed, total: total)
            }
        )
    }

    @objc func _segmentedControlValueChanged(_ segmentedControl: UISegmentedControl) {
        _start(with: urls[segmentedControl.selectedSegmentIndex])
    }

    @objc func _refresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
            self._start(with: self.urls[self.segmentedControl.selectedSegmentIndex])
        }
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

    func updateProgress(completed: Int64, total: Int64) {
        let text = NSMutableAttributedString(string: "")
        text.append(NSAttributedString(
            string: "Downloaded: ",
            attributes: [.font: UIFont.boldSystemFont(ofSize: 18)]
        ))
        let completed = ByteCountFormatter.string(fromByteCount: completed, countStyle: .binary)
        let total = ByteCountFormatter.string(fromByteCount: total, countStyle: .binary)
        text.append(NSAttributedString(
            string: "\(completed) / \(total)",
            attributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular)]
        ))
        labelProgress.attributedText = text
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
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
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
