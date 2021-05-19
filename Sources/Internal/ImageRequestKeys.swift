// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

extension ImageRequest {

    // MARK: - Cache Keys

    /// A key for processed image in memory cache.
    func makeImageCacheKey() -> ImageRequest.CacheKey {
        CacheKey(self)
    }

    /// A key for processed image data in disk cache.
    func makeDataCacheKey() -> String {
        "\(preferredImageId)\(ImageProcessors.Composition(processors).identifier)"
    }

    // MARK: - Load Keys

    /// A key for deduplicating operations for fetching the processed image.
    func makeImageLoadKey() -> ImageLoadKey {
        ImageLoadKey(
            cacheKey: CacheKey(self),
            options: options,
            loadKey: makeDataLoadKey()
        )
    }

    /// A key for deduplicating operations for fetching the original image.
    func makeDataLoadKey() -> DataLoadKey {
        DataLoadKey(request: self)
    }

    // MARK: - Internals (Keys)

    // Uniquely identifies a cache processed image.
    struct CacheKey: Hashable {
        let imageId: String?
        let processors: [ImageProcessing]

        init(_ request: ImageRequest) {
            self.imageId = request.preferredImageId
            self.processors = request.processors
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(imageId)
        }

        static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
            lhs.imageId == rhs.imageId && lhs.processors == rhs.processors
        }
    }

    // Uniquely identifies a task of retrieving the processed image.
    struct ImageLoadKey: Hashable {
        let cacheKey: CacheKey
        let options: ImageRequest.Options
        let loadKey: DataLoadKey
    }

    // Uniquely identifies a task of retrieving the original image dataa.
    struct DataLoadKey: Hashable {
        let request: ImageRequest

        func hash(into hasher: inout Hasher) {
            hasher.combine(request.preferredImageId)
        }

        static func == (lhs: DataLoadKey, rhs: DataLoadKey) -> Bool {
            Parameters(lhs.request) == Parameters(rhs.request)
        }

        private struct Parameters: Hashable {
            let imageId: String?
            let cachePolicy: URLRequest.CachePolicy
            let allowsCellularAccess: Bool

            init(_ request: ImageRequest) {
                self.imageId = request.imageId
                switch request.resource {
                case .url, .publisher:
                    self.cachePolicy = .useProtocolCachePolicy
                    self.allowsCellularAccess = true
                case let .urlRequest(urlRequest):
                    self.cachePolicy = urlRequest.cachePolicy
                    self.allowsCellularAccess = urlRequest.allowsCellularAccess
                }
            }
        }
    }
}

struct ImageProcessingKey: Equatable, Hashable {
    let imageId: ObjectIdentifier
    let processorId: AnyHashable

    init(image: ImageResponse, processor: ImageProcessing) {
        self.imageId = ObjectIdentifier(image)
        self.processorId = processor.hashableIdentifier
    }
}
