// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke
import NukeAlamofirePlugin

class AlamofireDemoViewController: BasicDemoViewController {    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        manager = {
            let loader = Nuke.Loader(loader: NukeAlamofirePlugin.DataLoader(), decoder: Nuke.DataDecoder(), cache: Cache.shared)
            return Manager(loader: loader, cache: Cache.shared)
        }()
    }
}
