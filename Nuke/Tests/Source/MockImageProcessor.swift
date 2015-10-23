//
//  MockImageProcessor.swift
//  Nuke
//
//  Created by Alexander Grebenyuk on 06/10/15.
//  Copyright © 2015 CocoaPods. All rights reserved.
//

import Foundation
import Nuke

extension Image {
    var nk_test_processorIDs: [String] {
        get {
            return (objc_getAssociatedObject(self, &AssociatedKeys.ProcessorIDs) as? [String]) ?? [String]()
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.ProcessorIDs, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

private struct AssociatedKeys {
    static var ProcessorIDs = "nk_test_processorIDs"
}

class MockImageProcessor: ImageProcessing {
    let ID: String
    init(ID: String) {
        self.ID = ID
    }
    func processImage(image: Image) -> Image? {
        var processorIDs: [String] = image.nk_test_processorIDs
        processorIDs.append(self.ID)
        let processedImage = Image()
        processedImage.nk_test_processorIDs = processorIDs
        return processedImage
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
