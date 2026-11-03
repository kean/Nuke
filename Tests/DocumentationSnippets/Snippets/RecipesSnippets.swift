// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Customization/recipes.md`.

import Foundation
import ImageIO
import Nuke
import NukeUI
import SwiftUI
import os

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Fallback

private struct AvatarView: View {
    let url: URL
    let fallback: URL

    var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else if state.error != nil {
                LazyImage(url: fallback)
            } else {
                Color.gray
            }
        }
    }
}

extension ImageRequest.UserInfoKey {
    static let alternatives: ImageRequest.UserInfoKey = "com.example.alternatives"
}

/// Loads the request, and then each of `alternatives`, until one succeeds.
struct FallbackDataLoader: DataLoading {
    var base: any DataLoading
    var alternatives: [URL]

    func loadData(
        with request: URLRequest,
        didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        completion: @escaping @Sendable (Error?) -> Void
    ) -> any Cancellable {
        let load = FallbackLoad()
        start(request, alternatives[...], load, didReceiveData, completion)
        return load
    }

    private func start(
        _ request: URLRequest,
        _ rest: ArraySlice<URL>,
        _ load: FallbackLoad,
        _ didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void,
        _ completion: @escaping @Sendable (Error?) -> Void
    ) {
        let inner = base.loadData(with: request, didReceiveData: { data, response in
            load.didReceiveData()
            didReceiveData(data, response)
        }, completion: { error in
            guard error != nil, load.canFallBack, let url = rest.first else {
                return completion(error)
            }
            var next = request
            next.url = url
            start(next, rest.dropFirst(), load, didReceiveData, completion)
        })
        load.track(inner)
    }
}

/// The attempt in flight.
final class FallbackLoad: Cancellable {
    private struct State {
        var inner: (any Cancellable)?
        var hasData = false
        var isCancelled = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// The pipeline appends every chunk, so a source that delivered data can't
    /// be replaced by another one.
    var canFallBack: Bool { state.withLock { !$0.hasData && !$0.isCancelled } }

    func didReceiveData() {
        state.withLock { $0.hasData = true }
    }

    func track(_ inner: any Cancellable) {
        let isCancelled = state.withLock {
            $0.inner = inner
            return $0.isCancelled
        }
        if isCancelled { inner.cancel() }
    }

    func cancel() {
        let inner = state.withLock {
            $0.isCancelled = true
            return $0.inner
        }
        inner?.cancel()
    }
}

final class FallbackDelegate: Sendable {}

extension FallbackDelegate: ImagePipeline.Delegate {
    func dataLoader(for request: ImageRequest, pipeline: ImagePipeline) -> any DataLoading {
        FallbackDataLoader(
            base: pipeline.configuration.dataLoader,
            alternatives: request.userInfo[.alternatives] as? [URL] ?? []
        )
    }
}

private func alternatives(url: URL, mirror: URL, secondMirror: URL) async throws {
    let pipeline = ImagePipeline(delegate: FallbackDelegate())
    
    var request = ImageRequest(url: url)
    request.userInfo[.alternatives] = [mirror, secondMirror]
    let image = try await pipeline.image(for: request)
    _ = image
}

// MARK: - Low Data Mode

func isConstrained(_ error: ImagePipeline.Error?) -> Bool {
    (error?.dataLoadingError as? URLError)?.networkUnavailableReason == .constrained
}

private struct LowDataImage: View {
    let url: URL
    let lowDataURL: URL

    private var request: ImageRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.allowsConstrainedNetworkAccess = false
        return ImageRequest(urlRequest: urlRequest)
    }

    var body: some View {
        LazyImage(request: request) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else if isConstrained(state.error) {
                LazyImage(url: lowDataURL)
            }
        }
    }
}

// MARK: - Per-Request Lifetime

extension ImageRequest.UserInfoKey {
    static let isShortLived: ImageRequest.UserInfoKey = "com.example.is-short-lived"
}

final class LifetimeDelegate: Sendable {
    let shortLived: ImageCache

    init(ttl: TimeInterval = 60) {
        shortLived = ImageCache()
        shortLived.ttl = ttl
    }
}

extension LifetimeDelegate: ImagePipeline.Delegate {
    func imageCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any ImageCaching)? {
        request.userInfo[.isShortLived] != nil ? shortLived : pipeline.configuration.imageCache
    }
}

// MARK: - Pinning

extension ImageRequest.UserInfoKey {
    static let isPinned: ImageRequest.UserInfoKey = "com.example.is-pinned"
}

final class PinningDelegate: Sendable {
    let regular: DataCache
    let pinned: DataCache

    init() throws {
        regular = try DataCache(name: "com.example.images")
        pinned = try DataCache(name: "com.example.pinned")
        pinned.isSweepEnabled = false
    }
}

extension PinningDelegate: ImagePipeline.Delegate {
    func dataCache(for request: ImageRequest, pipeline: ImagePipeline) -> (any DataCaching)? {
        request.userInfo[.isPinned] != nil ? pinned : regular
    }
}

private func installPinningDelegate() throws {
    ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(), delegate: try PinningDelegate())
}

// MARK: - Memory Limit

extension ImageRequest {
    /// Limits the longest side, so that a decoded image can't exceed `bytes`
    /// at 4 bytes per pixel. A square is the worst case.
    mutating func limitMemory(to bytes: Int) {
        thumbnail = ThumbnailOptions(maxPixelSize: floor(sqrt(CGFloat(bytes) / 4)))
    }
}

// MARK: - HDR

#if canImport(UIKit) && !os(watchOS)
@available(iOS 17, tvOS 17, *)
struct HDRDecoder: ImageDecoding {
    func decode(_ data: Data) throws -> ImageContainer {
        let options = [kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw ImageDecodingError.unknown
        }
        return ImageContainer(image: UIImage(cgImage: image))
    }
}

final class HDRDelegate: Sendable {}

@available(iOS 17, tvOS 17, *)
extension HDRDelegate: ImagePipeline.Delegate {
    func imageDecoder(for context: ImageDecodingContext, pipeline: ImagePipeline) -> (any ImageDecoding)? {
        context.isCompleted ? HDRDecoder() : nil
    }

    func shouldDecompress(response: ImageResponse, for request: ImageRequest, pipeline: ImagePipeline) -> Bool {
        false // Decompression can draw the image in 8 bits
    }
}

@available(iOS 17, tvOS 17, *)
@MainActor
private func displayHDR(in imageView: UIImageView) {
    imageView.preferredImageDynamicRange = .high
}
#endif
