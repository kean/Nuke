// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

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

class MockImageProcessor: ImageProcessing {
    var identifier: String

    init(id: String) {
        self.identifier = id
    }
    func process(image: Image, context: ImageProcessingContext) -> Image? {
        var processorIDs: [String] = image.nk_test_processorIDs
        processorIDs.append(identifier)
        let processedImage = Image()
        processedImage.nk_test_processorIDs = processorIDs
        return processedImage
    }
}

// MARK: - MockFailingProcessor

class MockFailingProcessor: ImageProcessing {
    func process(image: Image, context: ImageProcessingContext) -> Image? {
        return nil
    }

    var identifier: String {
        return "MockFailingProcessor"
    }
}

// MARK: - MockEmptyImageProcessor

class MockEmptyImageProcessor: ImageProcessing {
    let identifier = "MockEmptyImageProcessor"

    func process(image: Image, context: ImageProcessingContext) -> Image? {
        return image
    }

    static func == (lhs: MockEmptyImageProcessor, rhs: MockEmptyImageProcessor) -> Bool {
        return true
    }
}
