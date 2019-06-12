// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke
import DFCache

final class CustomCacheDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        pipeline = ImagePipeline {
            let conf = URLSessionConfiguration.default
            conf.urlCache = nil // Disable native URLCache
            $0.dataLoader = DataLoader(configuration: conf)

            $0.dataCache = DFCache(name: "com.github.kean.Nuke.DFCache", memoryCache: nil)
        }
    }
}

extension DFCache: DataCaching {
    public func cachedData(for key: String) -> Data? {
        return self.cachedData(forKey: key)
    }

    public func storeData(_ data: Data, for key: String) {
        self.store(data, forKey: key)
    }
}
