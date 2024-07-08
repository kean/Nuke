// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

extension PlatformImage {
    public var nk_test_processorIDs: [String] {
        get {
            return (objc_getAssociatedObject(self, AssociatedKeys.processorId) as? [String]) ?? [String]()
        }
        set {
            objc_setAssociatedObject(self, AssociatedKeys.processorId, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

private enum AssociatedKeys {
#if swift(>=5.10)
    // Safe because it's never mutated.
    nonisolated(unsafe) static let processorId = malloc(1)!
#else
    static let processorId = malloc(1)!
#endif
}

// MARK: - MockImageProcessor

public final class MockImageProcessor: ImageProcessing, CustomStringConvertible {
    public let identifier: String

    public init(id: String) {
        self.identifier = id
    }

    public func process(_ image: PlatformImage) -> PlatformImage? {
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

    public var description: String {
        "MockImageProcessor(id: \(identifier))"
    }
}

// MARK: - MockFailingProcessor

public final class MockFailingProcessor: ImageProcessing {
    public init() {}

    public func process(_ image: PlatformImage) -> PlatformImage? {
        nil
    }

    public var identifier: String {
        "MockFailingProcessor"
    }
}

public struct MockError: Error, Equatable {
    public let description: String

    public init(description: String) {
        self.description = description
    }
}

// MARK: - MockEmptyImageProcessor

public final class MockEmptyImageProcessor: ImageProcessing {
    public let identifier = "MockEmptyImageProcessor"

    public init() {}

    public func process(_ image: PlatformImage) -> PlatformImage? {
        image
    }

    public static func == (lhs: MockEmptyImageProcessor, rhs: MockEmptyImageProcessor) -> Bool {
        true
    }
}

// MARK: - MockProcessorFactory

/// Counts number of applied processors
public final class MockProcessorFactory {
    public private(set) var numberOfProcessorsApplied: Int = 0
    let lock = NSLock()

    public init() {}

    private final class Processor: ImageProcessing, @unchecked Sendable {
        var identifier: String { processor.identifier }
        var factory: MockProcessorFactory!
        let processor: MockImageProcessor

        init(id: String) {
            self.processor = MockImageProcessor(id: id)
        }

        func process(_ image: PlatformImage) -> PlatformImage? {
            factory.lock.lock()
            factory.numberOfProcessorsApplied += 1
            factory.lock.unlock()
            return processor.process(image)
        }
    }

    public func make(id: String) -> any ImageProcessing {
        let processor = Processor(id: id)
        processor.factory = self
        return processor
    }
}
