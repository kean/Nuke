//
//  MockImageProcessor.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 06/10/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import Nuke

class MockProcessedImage: UIImage {
    let processorIDs: [String]
    let image: UIImage
    init(image: UIImage, processorIDs: [String]) {
        self.processorIDs = processorIDs
        self.image = image
        super.init()
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class MockImageProcessor: ImageProcessing {
    let ID: String
    init(ID: String) {
        self.ID = ID
    }
    func processImage(image: UIImage) -> UIImage? {
        var processorIDs: [String] = (image as? MockProcessedImage)?.processorIDs ?? [String]()
        processorIDs.append(self.ID)
        return MockProcessedImage(image: image, processorIDs: processorIDs)
    }
}

func ==(lhs: MockImageProcessor, rhs: MockImageProcessor) -> Bool {
    return lhs.ID == rhs.ID
}
