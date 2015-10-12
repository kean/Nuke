//
//  AlamofireDemoViewController.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 18/09/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import Nuke
import NukeAlamofirePlugin

class AlamofireDemoViewController: BasicDemoViewController {
    var previousManager: ImageManager!
    
    deinit {
        ImageManager.shared = self.previousManager
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.previousManager = ImageManager.shared
        
        ImageManager.shared = (ImageManager(configuration: ImageManagerConfiguration(dataLoader: AlamofireImageDataLoader())))
    }
}
