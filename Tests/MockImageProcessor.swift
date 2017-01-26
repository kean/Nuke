// The MIT License (MIT)
//
// Copyright (c) 2017 Alexander Grebenyuk (github.com/kean).

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

// MARK: - MockImageProcessor

class MockImageProcessor: Processing {
    let ID: String
    init(ID: String) {
        self.ID = ID
    }
    func process(_ image: Image) -> Image? {
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

// MARK: - MockFailingProcessor

class MockFailingProcessor: Nuke.Processing {
    func process(_ image: Image) -> Image? {
        return nil
    }
}

func ==(lhs: MockFailingProcessor, rhs: MockFailingProcessor) -> Bool {
    return true
}

