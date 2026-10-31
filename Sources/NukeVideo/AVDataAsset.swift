// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import AVKit
import Foundation

// NukeVideo extends Nuke types, so `import NukeVideo` is enough to use it.
@_exported import Nuke

extension AssetType {
    /// Returns `true` if the asset represents a video file.
    public var isVideo: Bool {
        self == .mp4 || self == .m4v || self == .mov
    }
}

#if !os(watchOS)

private extension AssetType {
    var avFileType: AVFileType? {
        switch self {
        case .mp4: return .mp4
        case .m4v: return .m4v
        case .mov: return .mov
        default: return nil
        }
    }
}

// This class keeps strong pointer to DataAssetResourceLoader.
// Unchecked only because `AVURLAsset` is: a subclass has to restate what it
// inherits. The delegate it adds is checked.
final class AVDataAsset: AVURLAsset, @unchecked Sendable {
    private let resourceLoaderDelegate: DataAssetResourceLoader

    init(data: Data, type: AssetType?) {
        self.resourceLoaderDelegate = DataAssetResourceLoader(
            data: data,
            contentType: type?.avFileType?.rawValue ?? AVFileType.mp4.rawValue
        )

        // The URL is irrelevant
        let url = URL(string: "in-memory-data://\(UUID().uuidString)") ?? URL(fileURLWithPath: "/dev/null")
        super.init(url: url, options: nil)

        resourceLoader.setDelegate(resourceLoaderDelegate, queue: .global())
    }
}

// This allows LazyImage to play video from memory.
private final class DataAssetResourceLoader: NSObject, AVAssetResourceLoaderDelegate, Sendable {
    private let data: Data
    private let contentType: String

    init(data: Data, contentType: String) {
        self.data = data
        self.contentType = contentType
    }

    // MARK: - DataAssetResourceLoader

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        if let contentRequest = loadingRequest.contentInformationRequest {
            contentRequest.contentType = contentType
            contentRequest.contentLength = Int64(data.count)
            contentRequest.isByteRangeAccessSupported = true
        }

        if let dataRequest = loadingRequest.dataRequest {
            // The offsets count from the start of the resource, while the indices
            // of `data` start at `startIndex` when it is a slice. The range is
            // clamped because the first request asks for two bytes whatever the
            // content length, and there may be fewer.
            let start = min(Int(dataRequest.requestedOffset), data.count)
            let end = dataRequest.requestsAllDataToEndOfResource ? data.count : min(start + dataRequest.requestedLength, data.count)
            dataRequest.respond(with: data[(data.startIndex + start)..<(data.startIndex + end)])
        }

        loadingRequest.finishLoading()

        return true
    }
}

#endif
