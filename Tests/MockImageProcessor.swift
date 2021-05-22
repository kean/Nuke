// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension PlatformImage {
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

class MockImageProcessor: ImageProcessing, CustomStringConvertible {
    var identifier: String

    init(id: String) {
        self.identifier = id
    }

    func process(_ image: PlatformImage) -> PlatformImage? {
        var processorIDs: [String] = image.nk_test_processorIDs
        #if os(macOS)
        let processedImage = image.copy() as! PlatformImage
        #else
        guard let copy = image.cgImage?.copy() else {
            return image
        }
        let processedImage = PlatformImage(cgImage: copy)
        #endif
        processorIDs.append(identifier)
        processedImage.nk_test_processorIDs = processorIDs
        return processedImage
    }

    var description: String {
        "MockImageProcessor(id: \(identifier))"
    }
}

// MARK: - MockFailingProcessor

class MockFailingProcessor: ImageProcessing {
    func process(_ image: PlatformImage) -> PlatformImage? {
        return nil
    }

    var identifier: String {
        return "MockFailingProcessor"
    }
}

// MARK: - MockEmptyImageProcessor

class MockEmptyImageProcessor: ImageProcessing {
    let identifier = "MockEmptyImageProcessor"

    func process(_ image: PlatformImage) -> PlatformImage? {
        return image
    }

    static func == (lhs: MockEmptyImageProcessor, rhs: MockEmptyImageProcessor) -> Bool {
        return true
    }
}

// MARK: - MockProcessorFactory

/// Counts number of applied processors
final class MockProcessorFactory {
    var numberOfProcessorsApplied: Int = 0
    let lock = NSLock()

    private final class Processor: MockImageProcessor {
        var factory: MockProcessorFactory!

        override func process(_ image: PlatformImage) -> PlatformImage? {
            factory.lock.lock()
            factory.numberOfProcessorsApplied += 1
            factory.lock.unlock()
            return super.process(image)
        }
    }

    func make(id: String) -> MockImageProcessor {
        let processor = Processor(id: id)
        processor.factory = self
        return processor
    }
}
