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

            #if swift(>=4.2)
            $0.dataCache = try! DataCache(name: "com.github.kean.Nuke.DataCache")
            #else
            $0.dataCache = try! DataCache(
                name: "com.github.kean.Nuke.DataCache",
                filenameGenerator: {
                    guard let data = $0.cString(using: .utf8) else { return nil }
                    return _nuke_sha1(data, UInt32(data.count))
            })
            #endif
        }
    }
}
