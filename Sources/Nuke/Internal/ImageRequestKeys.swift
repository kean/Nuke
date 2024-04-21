// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Uniquely identifies a cache processed image.
final class MemoryCacheKey: Hashable, Sendable {
    // Using a reference type turned out to be significantly faster
    private let imageId: String?
    private let scale: Float
    private let thumbnail: ImageRequest.ThumbnailOptions?
    private let processors: [any ImageProcessing]

    init(_ request: ImageRequest) {
        self.imageId = request.preferredImageId
        self.scale = request.scale ?? 1
        self.thumbnail = request.thumbnail
        self.processors = request.processors
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(imageId)
        hasher.combine(scale)
        hasher.combine(thumbnail)
        hasher.combine(processors.count)
    }

    static func == (lhs: MemoryCacheKey, rhs: MemoryCacheKey) -> Bool {
        lhs.imageId == rhs.imageId && lhs.scale == rhs.scale && lhs.thumbnail == rhs.thumbnail && lhs.processors == rhs.processors
    }
}

// MARK: - Identifying Tasks

/// Uniquely identifies a task of retrieving the processed image.
final class TaskLoadImageKey: Hashable, Sendable {
    private let loadKey: TaskFetchOriginalImageKey
    private let options: ImageRequest.Options
    private let processors: [any ImageProcessing]

    init(_ request: ImageRequest) {
        self.loadKey = TaskFetchOriginalImageKey(request)
        self.options = request.options
        self.processors = request.processors
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(loadKey.hashValue)
        hasher.combine(options.hashValue)
        hasher.combine(processors.count)
    }

    static func == (lhs: TaskLoadImageKey, rhs: TaskLoadImageKey) -> Bool {
        lhs.loadKey == rhs.loadKey && lhs.options == rhs.options && lhs.processors == rhs.processors
    }
}

/// Uniquely identifies a task of retrieving the original image.
struct TaskFetchOriginalImageKey: Hashable {
    private let dataLoadKey: TaskFetchOriginalDataKey
    private let scale: Float
    private let thumbnail: ImageRequest.ThumbnailOptions?

    init(_ request: ImageRequest) {
        self.dataLoadKey = TaskFetchOriginalDataKey(request)
        self.scale = request.scale ?? 1
        self.thumbnail = request.thumbnail
    }
}

/// Uniquely identifies a task of retrieving the original image data.
struct TaskFetchOriginalDataKey: Hashable {
    private let imageId: String?
    private let cachePolicy: URLRequest.CachePolicy
    private let allowsCellularAccess: Bool

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
