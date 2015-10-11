//
//  MockImageProcessor.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 06/10/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import Nuke

class MockProcessedImage: Image {
    let processorIDs: [String]
    let image: Image
    init(image: Image, processorIDs: [String]) {
        self.processorIDs = processorIDs
        self.image = image
        #if !os(OSX)
            super.init()
        #else
            super.init(size: NSSize(width: 100, height: 100))
        #endif
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    #if os(OSX)    
    required init?(pasteboardPropertyList propertyList: AnyObject, ofType type: String) {
        fatalError("init(pasteboardPropertyList:ofType:) has not been implemented")
    }
    #endif
}

class MockImageProcessor: ImageProcessing {
    let ID: String
    init(ID: String) {
        self.ID = ID
    }
    func processImage(image: Image) -> Image? {
        var processorIDs: [String] = (image as? MockProcessedImage)?.processorIDs ?? [String]()
        processorIDs.append(self.ID)
        return MockProcessedImage(image: image, processorIDs: processorIDs)
    }
}

func ==(lhs: MockImageProcessor, rhs: MockImageProcessor) -> Bool {
    return lhs.ID == rhs.ID
}

class MockParameterlessImageProcessor: ImageProcessing {
    func processImage(image: Image) -> Image? {
        return image
    }
}
