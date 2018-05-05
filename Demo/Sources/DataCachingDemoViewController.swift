// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke

final class DataCachingDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        pipeline = ImagePipeline {
            $0.dataLoader = DataLoader(configuration: {
                // Disable disk caching built into URLSession
                let conf = DataLoader.defaultConfiguration
                conf.urlCache = nil
                return conf
            }())

            $0.imageCache = ImageCache()

            $0.enableExperimentalAggressiveDiskCaching(
                keyEncoder: {
                    guard let data = $0.cString(using: .utf8) else { return nil }
                    return _nuke_sha1(data, UInt32(data.count))
            })
        }
    }
}
