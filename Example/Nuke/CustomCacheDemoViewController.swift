//
//  CustomCacheDemoViewController.swift
//  Nuke Demo
//
//  Created by Alexander Grebenyuk on 18/03/16.
//  Copyright © 2016 CocoaPods. All rights reserved.
//

import Foundation
import Nuke
import DFCache

class CustomCacheDemoViewController: BasicDemoViewController {
    var previousManager: ImageManager!

    deinit {
        ImageManager.shared = self.previousManager
    }


    override func viewDidLoad() {
        super.viewDidLoad()

        self.previousManager = ImageManager.shared

        var managerConf = self.previousManager.configuration

        var loaderConf = (managerConf.loader as! ImageLoader).configuration
        loaderConf.cache = DFDiskCache(name: "test")

        managerConf.loader = ImageLoader(configuration: loaderConf)

        ImageManager.shared = (ImageManager(configuration: managerConf))
    }

}