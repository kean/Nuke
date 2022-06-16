// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImageProcessors {
    /// Composes multiple processors.
    public struct Composition: ImageProcessing, Hashable, CustomStringConvertible {
        let processors: [any ImageProcessing]

        /// Composes multiple processors.
        public init(_ processors: [any ImageProcessing]) {
            // note: multiple compositions are not flatten by default.
            self.processors = processors
        }

        /// Processes the given image by applying each processor in an order in
        /// which they were added. If one of the processors fails to produce
        /// an image the processing stops and `nil` is returned.
        public func process(_ image: PlatformImage) -> PlatformImage? {
            processors.reduce(image) { image, processor in
                autoreleasepool {
                    image.flatMap(processor.process)
                }
            }
        }

        /// Processes the given image by applying each processor in an order in
        /// which they were added. If one of the processors fails to produce
        /// an image the processing stops and an error is thrown.
        public func process(_ container: ImageContainer, context: ImageProcessingContext) throws -> ImageContainer {
            try processors.reduce(container) { container, processor in
                try autoreleasepool {
                    try processor.process(container, context: context)
                }
            }
        }

        /// Returns combined identifier of all the underlying processors.
        public var identifier: String {
            processors.map({ $0.identifier }).joined()
        }

        /// Creates a combined hash of all the given processors.
        public func hash(into hasher: inout Hasher) {
            for processor in processors {
                hasher.combine(processor.hashableIdentifier)
            }
        }

        /// Compares all the underlying processors for equality.
        public static func == (lhs: Composition, rhs: Composition) -> Bool {
            lhs.processors == rhs.processors
        }

        public var description: String {
            "Composition(processors: \(processors))"
        }
    }
}
