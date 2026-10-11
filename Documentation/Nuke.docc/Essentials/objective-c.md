# Objective-C

Call Nuke from Objective-C by adding a small bridge to your app.

## Overview

The API is Swift-only, and none of it is representable in the Objective-C runtime: ``ImageRequest`` is a struct, `ImagePipeline.image(for:)` is `async` and uses typed throws, ``ImageTask`` publishes progress as an `AsyncStream`, and `ImagePipeline.Error` is an enum with associated values. There is no `NukeObjC` module.

That's deliberate. A bridging module would be a second public API mirroring every type in the first, and it would lag behind it — every feature designed around structured concurrency would arrive there late or not at all. The bridge belongs in your app instead, where you know which handful of calls you actually need. In practice that's well under a hundred lines of Swift.

## Adding the Bridge

Add a Swift file to your app target. Mark the entry points `@objc` and give them explicit selectors so they read naturally on the Objective-C side.

```swift
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
```

The `ImageLoader.Handle` that `load` returns is a Swift struct, so it can't cross into Objective-C directly. Wrap it if callers need to cancel:

```swift
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
```

## Calling It from Objective-C

Import your app's generated Swift header and call the facade:

```objc
#import "MyApp-Swift.h"

- (void)configureWithURL:(NSURL *)url {
    [NKImageLoader loadImageWithURL:url intoView:self.imageView];
}
```

Cell reuse needs no extra bookkeeping — starting a new load into a view cancels the previous one:

```objc
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ImageCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Cell"
                                                               forIndexPath:indexPath];
    [NKImageLoader loadImageWithURL:self.urls[indexPath.item] intoView:cell.imageView];
    return cell;
}
```

With a placeholder and a completion handler:

```objc
[NKImageLoader loadImageWithURL:url
                    placeholder:[UIImage imageNamed:@"placeholder"]
                       intoView:self.imageView
                     completion:^(UIImage *image, NSError *error) {
    if (error != nil) {
        NSLog(@"Failed to load image: %@", error.localizedDescription);
    }
}];
```

## Prefetching

``ImagePrefetcher`` wraps the same way and plugs straight into `UICollectionViewDataSourcePrefetching`:

```swift
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
```

## Errors

Swift errors bridge to `NSError` automatically, but the synthesized `localizedDescription` is generic. `ImagePipeline.Error` conforms to `CustomStringConvertible`, so map it yourself to give Objective-C callers a useful message:

```swift
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
```

> Note: Typed throws don't survive a `Task` closure — `catch` there binds `any Error`, not `ImagePipeline.Error`. That's why the helper above tests the type rather than relying on inference.

## Threading

`ImageLoader` is `@MainActor`, so the facade is too. Objective-C has no way to enforce that, and a call from a background thread is a crash rather than a compile error. Keep every call on the main thread, or hop inside the bridge if your callers can't guarantee it.

## What Doesn't Bridge

| Swift API | Why | Bridge it with |
|---|---|---|
| ``ImageRequest`` | Struct | Separate parameters, or an `NSObject` wrapper |
| `ImagePipeline.image(for:)` | `async` + typed throws | A completion handler |
| ``ImageTask`` | Not an `NSObject` subclass | An `NSObject` wrapper |
| `ImageTask.progress`, `.previews`, `.events` | `AsyncStream` | A progress block |
| `ImagePipeline.Error` | Enum with associated values | `NSError`, as above |
| ``ImageResponse``, ``ImageContainer`` | Structs | Pass out `UIImage` and the fields you need |
| `ImageLoader.Handle` | Struct | An `NSObject` wrapper |
| `ImageLoader.Presentation` | Struct | Individual parameters |
| `[any ImageProcessing]` | Non-`@objc` existential | Build the request in Swift |

Anything not listed here follows the same rule: keep it in Swift and expose only the result.
