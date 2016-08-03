// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import DFCache

class CustomCacheDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let dataLoader = Nuke.CachingDataLoader(loader: Nuke.DataLoader(), cache: DFCache(name: "test", memoryCache: nil))
        let loader = Nuke.Loader(loader: dataLoader, decoder: Nuke.DataDecoder(), cache: Nuke.Cache.shared)
        manager = Manager(loader: loader, cache: Nuke.Cache.shared)
    }

}
