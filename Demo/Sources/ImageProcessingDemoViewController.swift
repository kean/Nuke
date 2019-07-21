// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

class ImageProcessingDemoViewController: UIViewController, ImagePipelineSettingsViewControllerDelegate {
    var pipeline = ImagePipeline.shared

    private let views: [[ImageProcessingView]] = [
        [ImageProcessingView(), ImageProcessingView()],
        [ImageProcessingView(), ImageProcessingView()],
        [ImageProcessingView(), ImageProcessingView()]
    ]

    private let refreshControl = UIRefreshControl()
    private let scrollView = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }

        let hStacks: [UIStackView] = views.map {
            let stack = UIStackView(arrangedSubviews: $0)
            stack.axis = .horizontal
            stack.distribution = .fillEqually
            stack.spacing = 16
            return stack
        }

        let vStack = UIStackView(arrangedSubviews: hStacks)
        vStack.axis = .vertical
        vStack.spacing = 32
        vStack.isLayoutMarginsRelativeArrangement = true
        vStack.layoutMargins = UIEdgeInsets(top: 32, left: 16, bottom: 32, right: 16)

        let scrollView = UIScrollView()
        scrollView.addSubview(vStack)
        vStack.pinToSuperview()

        view.addSubview(scrollView)
        scrollView.pinToSuperview()

        vStack.widthAnchor.constraint(equalTo: view.widthAnchor).isActive = true

        scrollView.refreshControl = refreshControl
        scrollView.refreshControl?.addTarget(self, action: #selector(refreshControlValueChanged), for: .valueChanged)
        scrollView.alwaysBounceVertical = true

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Configuration", style: .plain, target: self, action: #selector(buttonShowSettingsTapped))

        // Displaying images in a grid the way we want is a bit tricky on iOS so
        // we use aspect ratio is be sure it works correctly in all scenarios
        views[0][0].aspectRatio = 3/2
        views[0][1].aspectRatio = 3/2
        views[1][0].aspectRatio = 3/2
        views[1][1].aspectRatio = 3/2
        views[2][0].aspectRatio = 1
        views[2][1].aspectRatio = 1

        loadImages()
    }

    func loadImages() {
        loadImage(view: views[0][0], title: "Original", processors: [])

        let screenWidth = UIScreen.main.bounds.size.width / 3
        let targetSize = CGSize(width: screenWidth, height: (screenWidth * 2 / 3))
        loadImage(view: views[0][1], title: "Resize", processors: [
            ImageProcessor.Resize(size: targetSize)
        ])

        loadImage(view: views[1][0], title: "Rounded Corners", processors: [
            ImageProcessor.Resize(size: targetSize),
            ImageProcessor.RoundedCorners(radius: 8)
        ])

        loadImage(view: views[1][1], title: "Monochrome", processors: [
            ImageProcessor.Resize(size: targetSize),
            ImageProcessor.RoundedCorners(radius: 8),
            ImageProcessor.CoreImageFilter(name: "CIColorMonochrome",
                                           parameters: ["inputIntensity": 1,
                                                        "inputColor": CIColor(color: .white)],
                                           identifier: "nuke.demo.monochrome")
        ])

        loadImage(view: views[2][0], title: "Circle", processors: [
            ImageProcessor.Resize(size: targetSize),
            ImageProcessor.Circle()
        ])

        loadImage(view: views[2][1], title: "Blur", processors: [
            ImageProcessor.Resize(size: targetSize),
            ImageProcessor.Circle(),
            ImageProcessor.GaussianBlur(radius: 3)
        ])
    }

    func loadImage(view: ImageProcessingView, title: String, processors: [ImageProcessing]) {
        let request = ImageRequest(
            url: URL(string: "https://user-images.githubusercontent.com/1567433/59150453-178bbb80-8a24-11e9-94ca-fd8dff6e2a9a.jpeg")!,
            processors: processors
        )

        view.titleLabel.text = title

        var options = ImageLoadingOptions(transition: .fadeIn(duration: 0.5))
        options.pipeline = pipeline

        Nuke.loadImage(with: request, options: options, into: view.imageView)
    }

    // MARK: - Actions

    @objc func refreshControlValueChanged() {
        loadImages()
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.refreshControl.endRefreshing()
        }
    }

    @objc func buttonShowSettingsTapped() {
       ImagePipelineSettingsViewController.show(from: self, pipeline: pipeline)
    }

    // MARK: - ImagePipelineSettingsViewControllerDelegate

    func imagePipelineSettingsViewController(_ vc: ImagePipelineSettingsViewController, didFinishWithConfiguration configuration: ImagePipeline.Configuration) {
        self.pipeline = ImagePipeline(configuration: configuration)
        vc.dismiss(animated: true) {}
    }
}

class ImageProcessingView: UIView {
    let titleLabel = UILabel()
    let imageView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true

        let container = UIView()
        container.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.leftAnchor.constraint(equalTo: container.leftAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.rightAnchor.constraint(lessThanOrEqualTo: container.rightAnchor),
            imageView.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
        ])

        let stack = UIStackView(arrangedSubviews: [titleLabel, container])
        stack.axis = .vertical
        stack.spacing = 8

        addSubview(stack)
        stack.pinToSuperview()

        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 100)
        ])
    }

    var aspectRatio: CGFloat = 1 {
        didSet {
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor, multiplier: aspectRatio).isActive = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
