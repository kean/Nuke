//
//  AlamofireDemoViewController.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 18/09/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import Nuke

class AlamofireDemoViewController: BasicDemoViewController {
    var previousManager: ImageManaging!
    
    deinit {
        ImageManager.setShared(self.previousManager)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.previousManager = ImageManager.shared()
        
        ImageManager.setShared(ImageManager(configuration: ImageManagerConfiguration(dataLoader: AlamofireImageDataLoader())))
    }
}
