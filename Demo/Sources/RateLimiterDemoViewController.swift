// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

private let cellReuseID = "reuseID"

final class RateLimiterDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        itemsPerRow = 10

        pipeline = ImagePipeline {
            let urlSessionConf = URLSessionConfiguration.default
            urlSessionConf.urlCache = nil // disable disk cache
            $0.dataLoader = DataLoader(configuration: urlSessionConf)

            $0.imageCache = nil // disable memory cache

            $0.isDeduplicationEnabled = false // disable deduplication
        }

        for _ in 0..<10 {
            photos.append(contentsOf: photos)
        }
    }

    override func makeRequest(with url: URL, imageView: UIImageView) -> ImageRequest {
        return ImageRequest(url: url, processors: [ImageProcessor.Resize(size: imageView.bounds.size)])
    }

    override func makeImageLoadingOptions() -> ImageLoadingOptions {
        return ImageLoadingOptions() // no transition animations
    }
}
