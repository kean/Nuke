// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Essentials/objective-c.md`.

#if canImport(UIKit) && !os(watchOS)

import Foundation
import UIKit
import Nuke
import NukeUI

/// An Objective-C facade over the parts of Nuke this app uses.
///
/// The class is `@MainActor`, so call it from the main thread.
@objc(NKImageLoader)
@MainActor
public final class NKImageLoader: NSObject {

    /// Loads an image into a view, cancelling any previous load into that view.
    @objc(loadImageWithURL:intoView:)
    @discardableResult
    public static func loadImage(with url: URL, into view: UIImageView) -> NKImageTask {
        NKImageTask(ImageLoader.load(url, into: view))
    }

    /// Loads an image with a placeholder and a fade-in, reporting the outcome.
    @objc(loadImageWithURL:placeholder:intoView:completion:)
    public static func loadImage(
        with url: URL,
        placeholder: UIImage?,
        into view: UIImageView,
        completion: (@MainActor @Sendable (UIImage?, Error?) -> Void)?
    ) {
        let handle = ImageLoader.load(url, into: view, presentation: .init(
            placeholder: placeholder,
            transition: .fadeIn(duration: 0.25)
        ))
        guard let completion else { return }
        Task {
            switch await handle.result {
            case .success(let response): completion(response.image, nil)
            case .failure(let error): completion(nil, error.asNSError)
            }
        }
    }

    /// Cancels the load into the view.
    @objc(cancelRequestForView:)
    public static func cancelRequest(for view: UIImageView) {
        ImageLoader.loader(for: view).cancel()
    }

    /// Fetches an image without displaying it in a view.
    @objc(fetchImageWithURL:completion:)
    public static func image(for url: URL, completion: @escaping @MainActor @Sendable (UIImage?, Error?) -> Void) {
        Task {
            do {
                let image = try await ImagePipeline.shared.image(for: url)
                completion(image, nil)
            } catch {
                completion(nil, error.asNSError)
            }
        }
    }

    /// Returns an image from the memory cache, if there is one.
    @objc(cachedImageForURL:)
    public static func cachedImage(for url: URL) -> UIImage? {
        ImagePipeline.shared.cache[url]?.image
    }

    /// Removes everything from the memory and disk caches.
    @objc(removeAllCachedImages)
    public static func removeAllCachedImages() {
        ImagePipeline.shared.cache.removeAll()
    }
}

@objc(NKImageTask)
@MainActor
public final class NKImageTask: NSObject {
    private let handle: ImageLoader.Handle

    init(_ handle: ImageLoader.Handle) {
        self.handle = handle
    }

    @objc public func cancel() {
        handle.cancel()
    }
}

@objc(NKImagePrefetcher)
public final class NKImagePrefetcher: NSObject {
    private let prefetcher = ImagePrefetcher()

    @objc(startPrefetchingWithURLs:)
    public func startPrefetching(with urls: [URL]) {
        prefetcher.startPrefetching(with: urls)
    }

    @objc(stopPrefetchingWithURLs:)
    public func stopPrefetching(with urls: [URL]) {
        prefetcher.stopPrefetching(with: urls)
    }
}

private extension Error {
    var asNSError: NSError {
        guard let error = self as? ImagePipeline.Error else {
            return self as NSError
        }
        return NSError(domain: "com.github.kean.Nuke", code: 0, userInfo: [
            NSLocalizedDescriptionKey: error.description,
            NSUnderlyingErrorKey: error as NSError
        ])
    }
}

#endif
