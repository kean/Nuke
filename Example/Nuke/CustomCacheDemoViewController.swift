// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import DFCache

class CustomCacheDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        loader = Nuke.Loader(loader: Nuke.DataLoader(), decoder: Nuke.DataDecoder(), cache: DFCache(name: "test", memoryCache: nil))
    }

}
