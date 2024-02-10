# Nuke 12

## Nuke 12.4

*Feb 10, 2024*

## What's Changed
* Enable visionOS support for all APIs by @zachwaugh in https://github.com/kean/Nuke/pull/752
* Update documentation by @tkersey in https://github.com/kean/Nuke/pull/747

**Full Changelog**: https://github.com/kean/Nuke/compare/12.3.0...12.4.0

## Nuke 12.3

*Jan 6, 2024*

- Add support for visionOS by @bobek-balinek in https://github.com/kean/Nuke/pull/743

## Nuke 12.2

*Nov 23, 2023*

- Add another file type signature for .m4v files by @leonid-shevtsov in https://github.com/kean/Nuke/pull/735
- Added the onStart callback to SwiftUI.LazyImage by @urbaneewe in https://github.com/kean/Nuke/pull/736

## Nuke 12.1.6

*Aug 19, 2023*

- Improve `ImageCache` performance (20%)
- Improve `NukeExtensions` performance (5%)
- Update the code to support future visionOS releases by switching to `canImport` where possible

## Nuke 12.1.5

*Jul 29, 2023*

- Fix https://github.com/kean/Nuke/issues/717 by moving `DataCache` metadata to a hidden file - https://github.com/kean/Nuke/pull/718

## Nuke 12.1.4

*Jul 22, 2023*

- Upgrade to [`CryptoKit`](https://developer.apple.com/documentation/cryptokit) from `CommonCrypto` and slightly optimize how cryptographic hashes are converted to strings (used as filenames for `DataCache`)
- Deprecate `DataCache/isCompressionEnabled`. It was initially added as a general-purpose feature, but it's not recommended to be used with most image formats.
- `DataCache` now performs sweeps less frequently
- Minor docs correction – https://github.com/kean/Nuke/pull/715 by @tdkn

## Nuke 12.1.3

*Jul 10, 2023*

- Fix https://github.com/kean/Nuke/issues/709: `LazyImage` fails to perform memory cache lookup in some scenarios

## Nuke 12.1.2

*Jun 25, 2023*

- Fix https://github.com/kean/Nuke/issues/710: build failure on watchOS in debug mode – https://github.com/kean/Nuke/pull/711 by @FieryFlames

## Nuke 12.1.1

*Jun 22, 2023*

- Fix https://github.com/kean/Nuke/issues/693: `ImageRequest` created with an async function now executes it lazily - https://github.com/kean/Nuke/pull/708 by @khlopko
- Fix https://github.com/kean/Nuke/issues/695: `byCroppingToSquare()` always return square image – https://github.com/kean/Nuke/pull/696 by @zzmasoud
- Update unit tests – https://github.com/kean/Nuke/pull/701 by @woxtu 
- Fix upcoming warnings in Xcode 15

## Nuke 12.1

*Mar 25, 2023*

- Add `makeImageView` closure to `LazyImageView` to allow using custom views for rendering images
- Add `onCompletion` closure to `LazyImage` and `FetchImage`
- Fix an issue with `.videoAssetKey` value missing from `ImageContainer`
- Fix an issue with `.gif` being encoded as `.jpeg` when `.storeEncodedImages` policy is used 

## Nuke 12.0

*Mar 4, 2023*

Nuke 12 enhances the two main APIs introduced in the previous release: `LazyImage` and the async `ImagePipeline` methods. They are faster, more robust, and easier to use.

> The [migration guide](https://github.com/kean/Nuke/blob/nuke-12/Documentation/Migrations/Nuke%2012%20Migration%20Guide.md) is available to help with the update. The minimum requirements are unchanged from Nuke 11.

## Concurrency

Redesign the concurrency APIs making them more ergonomic and fully `Sendable` compliant.

- Add `ImagePipeline/imageTask(with:)` method that returns a new type `AsyncImageTask`

```swift
let task = ImagePipeline.shared.imageTask(with: URL(string: "example.com"))
task.priority = .high
for await progress in task.progress {
    print("Updated progress: ", progress)
}
let image = try await task.image
```

- The existing convenience `ImagePipeline/image(for:)` method now returns an image instead of `ImageResponse`
- Remove the `delegate` parameter from `ImagePipeline/image(for:)` method to address the upcoming concurrency warnings in Xcode 14.3
- Remove `ImageTaskDelegate` and move its methods to `ImagePipelineDelegate` and add the `pipeline` parameter

## NukeUI 2.0

NukeUI started as a separate [repo](https://github.com/kean/NukeUI), but the initial production version was released as part of [Nuke 11](https://github.com/kean/Nuke/releases/tag/11.0.0). Let's call it NukeUI 1.0. The framework was designed before the [`AsyncImage`](https://developer.apple.com/documentation/swiftui/asyncimage) announcement and had a few discrepancies that made it harder to migrate from `AsyncImage`. This release addresses the shortcomings of the original design and features a couple of performance improvements.

- `LazyImage` now uses `SwiftUI.Image` instead of `NukeUI.Image` backed by `UIImageView` and `NSImageView`. It eliminates any [discrepancies](https://github.com/kean/Nuke/issues/578) between `LazyImage` and `AsyncImage` layout and self-sizing behavior and fixes issues with `.redacted(reason:)`, `ImageRenderer`, and other SwiftUI APIs that don't work with UIKIt and AppKit based views.
- Remove `NukeUI.Image` so the name no longer [clashes](https://github.com/kean/Nuke/discussions/658) with `SwiftUI.Image`
- Fix [#669](https://github.com/kean/Nuke/issues/669): `redacted` not working for `LazyImage`
- GIF rendering is no longer included in the framework. Please consider using one of the frameworks that specialize in playing GIFs, such as [Gifu](https://github.com/kaishin/Gifu). It's easy to integrate, especially with `LazyImage`.
- Extract progress updates from `FetchImage` to a separate observable object, reducing the number of body reloads
- `LazyImage` now requires a single body calculation to render the response from the memory cache (instead of three before)
- Disable animations by default
- Fix an issue where the image won't reload if you change only `LazyImage` `processors` or `priority` without also changing the image source
- `FetchImage/image` now returns `Image` instead of `UIImage`
- Make `_PlatformImageView` internal (was public) and remove more typealiases

## Nuke

- Add a new initializer to `ImageRequest.ThumbnailOptions` that accepts the target size, unit, and content mode - [#677](https://github.com/kean/Nuke/pull/677)
- ImageCache uses 20% of available RAM which is quite aggressive. It's an OK default on iOS because it clears 90% of the used RAM when entering the background to be a good citizen. But it's not a good default on a Mac. Starting with Nuke 12, the default size is now strictly limited to 512 MB.
- `ImageDecoder` now defaults to scale `1` for images (configurable using [`UserInfoKey/scaleKey`](https://kean-docs.github.io/nuke/documentation/nuke/imagerequest/userinfokey/scalekey))
- Removes APIs deprecated in the previous versions
- Update the [Performance Guide](https://kean-docs.github.io/nuke/documentation/nuke/performance-guide)

## NukeVideo

Video playback can be significantly [more efficient](https://web.dev/replace-gifs-with-videos/) than playing animated GIFs. This is why the initial version of NukeUI provided support for basic video playback. But it is not something that the majority of the users need, so this feature was extracted to a separate module called `NukeVideo`.

There is now less code that you need to include in your project, which means faster compile time and smaller code size. With this and some other changes in Nuke 12, the two main frameworks – Nuke and NukeUI – now have 25% less code compared to Nuke 11. In addition to this change, there are a couple of improvements in how the precompiled binary frameworks are generated, significantly reducing their size.

- Move all video-related code to `NukeVideo`
- Remove `ImageContainer.asset`. The asset is now added to `ImageContainer/userInfo` under the new `.videoAssetKey`.
- Reduce the size of binary frameworks by up to 50%

# Nuke 11

## Nuke 11.6.4

*Feb 19, 2023*

- Fix [#671](https://github.com/kean/Nuke/pull/671): `ImagePipeline/image(for:)` hangs if you cancel the async Task before it is started 

## Nuke 11.6.3

*Feb 18, 2023*

- Fix warnings in Xcode 14.3

## Nuke 11.6.2

*Feb 9, 2023*

- Fix an issue with static GIFs not rendered correctly – [#667](https://github.com/kean/Nuke/pull/667) by [@Havhingstor](https://github.com/Havhingstor)

## Nuke 11.6.1

*Feb 5, 2023*

- Fix [#653](https://github.com/kean/Nuke/issues/653): ImageView wasn't calling `prepareForReuse` on its `animatedImageView`

## Nuke 11.6.0

*Jan 27, 2023*

- Fix [#579](https://github.com/kean/Nuke/issues/579): `ImageEncoders.ImageIO` losing image orientation - [#643](https://github.com/kean/Nuke/pull/643)
- Deprecate previously soft-deprecated `ImageRequestConvertible` - [#642](https://github.com/kean/Nuke/pull/642)
- Add `isCompressionEnabled` option to `DataCache` that enables compression using Apple’s [lzfse](https://en.wikipedia.org/wiki/LZFSE) algorithm
- Add `ExpressibleByStringLiteral` conformance to `ImageRequest`
- Make compatible with Swift 6 mode

## Nuke 11.5.3

*Jan 4, 2023*

- Remove DocC files to address https://github.com/kean/Nuke/issues/609

## Nuke 11.5.1

*Dec 25, 2022*

- Fix `ImagePipeline.shared` warning with Strit Concurrency Checking set to Complete
- Fix an issue where `ImagePrefetcher/didComplete` wasn't called in some scenarios
- `ImagePrefetcher/didComplete` is now called on the main queue

## Nuke 11.5.0

*Dec 17, 2022*

- `DataLoader/delegate` now gets called for all `URLSession/delegate` methods, not just the ones required by [Pulse](https://github.com/kean/Pulse). It allows you to modify `DataLoader` behavior in new ways, e.g. for handling authentication challenges.
- Add new unit tests, thanks to [@zzmasoud](https://github.com/zzmasoud) - [#626](https://github.com/kean/Nuke/pull/626)
- Fix an issue with `ImagePrefetcher/didComplete` not being called when images are in the memory cache, thanks to [@0xceed](https://github.com/0xceed) - [#635](https://github.com/kean/Nuke/pull/635)
- Move .docc folders back to Sources/, so that the Nuke docs are now again available in Xcode

## Nuke 11.4.1

*Dec 15, 2022*

- Correct the release commit/branch

## Nuke 11.4.0

*Dec 14, 2022*

- Add `isVideoFrameAnimationEnabled` option to NukeUI views, thanks to [@maciesielka](https://github.com/maciesielka) 

## Nuke 11.3.1

*Oct 22, 2022*

- Fix deprecated `withTaskCancellationHandler` usage - [#614](https://github.com/kean/Nuke/pull/614), thanks to [@swasta](https://github.com/swasta)
- Fix xcodebuild & docc build issue on Xcode 14.0.1 - [#609](https://github.com/kean/Nuke/issues/609)

## Nuke 11.3.0

*Sep 17, 2022*

- Add support for loading image into `TVPosterView` (tvOS) - [#602](https://github.com/kean/Nuke/pull/602), thanks to [@lukaskukacka](https://github.com/lukaskukacka)

## Nuke 11.2.1

*Sep 10, 2022*

- Fix an issue with Mac Catalyst on Xcode 14.0  

## Nuke 11.2.0

*Sep 10, 2022*

- Add support for Xcode 14.0
- Fix [#595](https://github.com/kean/Nuke/issues/595) – compilation issue on macOS

## Nuke 11.1.1

*Aug 16, 2022*

- **Breaking** Progressive decoding is now disabled by default as a way to mitigate [#572](https://github.com/kean/Nuke/issues/572)
- Add `prefersIncrementalDelivery` to `DataLoader`. When progressive decoding is disabled, it now uses `prefersIncrementalDelivery` on `URLSessionTask`, slightly increasing the performance
- Fix an issue with placeholder not being shown by `LazyImage` when the initial URL is `nil` – [#586](https://github.com/kean/Nuke/pull/586), thanks to @jeffreykuiken
- Add convenience options to `Image` and `LazyImage`: `resizingMode(_:)`, `videoRenderingEnabled(_:)`, `videoLoopingEnabled(_:)`, `animatedImageRenderingEnabled(_:)`
- Fix an issue where `AVPlayerLayer` was created eagerly
- Disable `prepareForDisplay` by default and add a configuration option to enable it

## Nuke 11.1.0

*Aug 7, 2022*

- Add `DataLoader` delegate for easy Pulse integration - [#583](https://github.com/kean/Nuke/pull/583)
- Add missing content mode to NukeUI - [#582](https://github.com/kean/Nuke/pull/582), thanks to [Ethan Pippin](https://github.com/LePips)

## Nuke 11.0.1

*Jul 24, 2022*

- Fix an issue with cancellation of requests created with Combine publishers - [#576](https://github.com/kean/Nuke/pull/576), thanks to [douknow](https://github.com/douknow)  

## Nuke 11.0.0

*Jul 20, 2022*

**Nuke 11** embraces **Swift Structured Concurrency** with full feature parity with legacy completion-based APIs. **NukeUI** is now part of the main repo. Docs were completely rewritten using DocC and hosted on GitHub: [Nuke](https://kean-docs.github.io/nuke/documentation/nuke/), [NukeUI](https://kean-docs.github.io/nukeui/documentation/nukeui/), [NukeExtensions](https://kean-docs.github.io/nukeextensions/documentation/nukeextensions/).

There are no major source-breaking changes in this release. Instead, it adds dozens of API refinements to make the framework more ergonomic.

- Increase the minimum supported Xcode version to 13.3
- Increase minimum supported platforms: iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15

### Structured Concurrency

Extend Async/Await APIs to have complete feature parity with the existing completion-based APIs paving the road for its eventual deprecation and removal in the future major versions.

- Add `@MainActor` to the following types: `FetchImage`, `LazyImage`, `LazyImageView`, Nuke `loadImage(into:)` method
- Add `Sendable` to most of the Nuke types, including `ImagePipeline`, `ImageRequest`,` ImageResponse`, `ImageContainer`, `ImageTask`, and more
- Add `ImageTaskDelegate` to achieve complete feature-parity with completion-based APIs - [#559](https://github.com/kean/Nuke/pull/559)
- `ImageRequest` now accepts async/await function to fetch data as a resource

Loading an image and monitoring download progress:

```swift
func loadImage() async throws {
    let response = try await pipeline.image(for: "https://example.com/image.jpeg", delegate: self)
}

func imageTaskCreated(_ task: ImageTask) {
    // You can capture the task instance here to change priority later, etc
}

func imageTask(_ task: ImageTask, didUpdateProgress progress: ImageTask.Progress) {
    // Update progress
}

func imageTask(_ task: ImageTask, didReceivePreview response: ImageResponse) {
    // Display progressively decoded image
}

// And more...
```

### NukeUI and NukeExtensions

**NukeUI** is now part of the main repo and the existing UIKit and AppKit UI extensions were moved from the main module to **NukeExtensions** and soft-deprecated.

- Move [NukeUI](https://github.com/kean/NukeUI) to the main Nuke repo
- Move `UIImageView` / `NSImageView` extensions to a separate target `NukeExtensions` and soft-deprecated them - [#555](https://github.com/kean/Nuke/pull/555)
- Remove deprecated APIs from NukeUI
- Add `ImageResponse` typealias to NukeUI
- Use new `ImageTask.Progress` in NukeUI
- NukeUI no longer exposes public Gifu dependency or its APIs

### Error Reporting Improvements

A complete overhaul of `ImagePipeline.Error` with many new cases covering every single point of failure in the pipeline.

- Add `throws` to "advanced" `ImageProcessing`
- Add `throws` to `ImageDecoding`
- Add support for throwing processing in `ImageProcessors.CoreImageFilter`
- Add `ImageDecoding` instance, `ImageDecodingContext`, and underlying error to `.decodingFailed` error case
- Add `ImageProcessingContext` and underlying error to `.processingFailed` error case
- Add `.dataMissingInCache` error case for a scenario where data is missing in cache and download is disabled using `.returnCacheDataDontLoad`.
- Add `.dataIsEmpty` error case for a scenario where the data loader doesn't report an error, but the response is empty.
- Add `.decoderNotRegistered(context:)` error case for a scenario where no decoders are registered for the downloaded data. This should never happen unless you remove the default decoder from the registry.
- Add `.imageRequestMissing` error case for a scenario when the load image method is called with no image request.
- Add `cacheType` to `ImageDecodingContext`

### Other Changes

- Fix [#511](https://github.com/kean/Nuke/issues/511) `OSAtomic` deprecation warnings - [#573](https://github.com/kean/Nuke/pull/573)
- Add `ImageTask.State`. Improve performance when canceling and changing priority of completed tasks.
- Add `ImageTask.Progress` to simplify progress reporting APIs
- Add `ImageRequest.Options.skipDecompression`
- Add public `ImageCacheKey` initializer with ``ImageRequest``
- Add `imageCache(for:pipeline:)` method to `ImagePipelineDelegate`
- Add automatic `hashableIdentifier` implementation to `ImageProcessing` types that implement `Hashable` protocol - [#563](https://github.com/kean/Nuke/pull/563)
- Add a way to customize decompression using `ImagePipelineDelegate`
- Add `ImageRequest` to `ImageResponse`
- Improve decompression performance by using [`preparingForDisplay`](https://developer.apple.com/documentation/uikit/uiimage/3750834-preparingfordisplay) on iOS 15 and tvOS 15
- Add metrics reporting using `DataLoaderObserving` protocol
- Add custom disk caching for requests backed by data publishers - [#553](https://github.com/kean/Nuke/pull/553)
- Add `.pipelineInvalidated` error that is thrown for new requests started on the invalidated pipeline
- Add public write access to `ImageDecodingContext`,  `ImageProcessingContext`, `ImageResponse` properties
- Add static `default` and `imageIO` functions to `ImageEncoding` protocol for easy creating of encoders
- Add `sizeLimit` to `withDataCache` `ImagePipeline.Configuration` initializer
- Make `ImageCache` `ttl` optional instead of using `0` as a "never expires" indicator

### Removals and Deprecations

- Soft-deprecate `ImageRequestConvertible` and use `ImageRequest` and `URL` directly in all news APIs for better discoverability and performance  - [#567](https://github.com/kean/Nuke/pull/567)
- Deprecate `ImageDecoderRegistering`
- Deprecate `ImageCaching` extension that works with `ImageRequest` 
- Rename `isFinal` in `ImageProcessingContext` to `isCompleted` to match the renaming APIs
- Rename `ImagePipeline/Configuration/DataCachePolicy` to `ImagePipeline/DataCachePolicy`
- Remove `ImageRequestConvertible` conformance from `String`
- Remove `ImageTaskEvent` and consolidate it with the new `ImageTaskDelegate` API - [#564](https://github.com/kean/Nuke/pull/564)
- Remove progress monitoring using `Foundation.Progress`
- Remove `WKInterfaceObject` support (in favor of SwiftUI)
- Remove `ImageType` typealias (deprecated in 10.5)
- Remove `Cancellable` conformance from `URLSessionTask`
- Remove public `ImagePublisher` class (make it internal)

### Non-Code Changes

- Automatically discover typos on CI - [#549](https://github.com/kean/Nuke/pull/549)
- Remove `CocoaPods` support

# Nuke 10

## Nuke 10.11.2

*Jun 9, 2022*

- Revert changes to the deployment targets introduced in Nuke 10.10.0

## Nuke 10.11.1

*Jun 9, 2022*

- Fix an issue with data not always being attached to an error when decoding fails

## Nuke 10.11.0

*Jun 8, 2022*

- Add associated `Data` to `ImagePipeline.Error.decodingFailed` - [#545](https://github.com/kean/Nuke/pull/545), thanks to [Shai Mishali](https://github.com/freak4pc)

> There are other major improvements to error reporting coming in [Nuke 11](https://github.com/kean/Nuke/pull/547)

## Nuke 10.10.0

*May 21, 2022*

- Remove APIs deprecated in Nuke 10.0
- Increase minimum deployment targets

## Nuke 10.9.0

*May 1, 2022*

- Rename async/await `loadImage(with:)` method to `image(for:)`, and `loadData(with:)` to `data(for:)`
- Add `Sendable` conformance to some of the types

## Nuke 10.8.0

*Apr 24, 2022*

- Add async/await support (requires Xcode 13.3) – [#532](https://github.com/kean/Nuke/pull/532)

```swift
extension ImagePipeline {
    public func loadImage(with request: ImageRequestConvertible) async throws -> ImageResponse
    public func loadData(with request: ImageRequestConvertible) async throws -> (Data, URLResponse?)
}

extension FetchImage {
    public func load(_ action: @escaping () async throws -> ImageResponse)
}
```

## Nuke 10.7.2

*Apr 23, 2022*

- Remove code deprecated in Nuke 9.4.1

## Nuke 10.7.1

*Jan 27, 2022*

- Fix intermittent SwiftUI crash in NukeUI/FetchImage 

## Nuke 10.7.0

*Jan 24, 2022*

- Fix M4V support – [#523](https://github.com/kean/Nuke/pull/523), thanks to [Son Changwoo](https://github.com/kor45cw)
- Make `ImagePrefetcher` `didComplete` closure public – [#528](https://github.com/kean/Nuke/pull/515), thanks to [Winston Du](https://github.com/winstondu)
- Rename internal `didEnterBackground` selector - [#531](https://github.com/kean/Nuke/issues/531)

## Nuke 10.6.1

*Dec 27, 2021*

- Remove async/await support

## Nuke 10.6.0

*Dec 27, 2021*

This release added async/await, but the change was [reverted](https://github.com/kean/Nuke/issues/526) in 10.6.1 (for CocoaPods) and the release was deleted in GitHub.

## Nuke 10.5.2

*Dec 2, 2021*

- Revert `preparingForDisplay` changes made in [#512](https://github.com/kean/Nuke/pull/512)
- Add URLSession & URLSessionDataTask descriptions - [#517](https://github.com/kean/Nuke/pull/517), thanks to [Stavros Schizas](https://github.com/sschizas)

## Nuke 10.5.1

*Oct 23, 2021*

- Fix build for Catalyst

## Nuke 10.5.0

*Oct 23, 2021*

- Improve image decompressiong performance on iOS 15 and tvOS 15 by using [preparingForDisplay()](https://developer.apple.com/documentation/uikit/uiimage/3750834-preparingfordisplay?language=o_5) (requires Xcode 13) - [#512](https://github.com/kean/Nuke/pull/512)
- On iOS 15, tvOS 15, image decompressiong now preserves 8 bits per pixel for grayscale images - [#512](https://github.com/kean/Nuke/pull/512)
- Adopt extended static member lookup ([SE-0299](https://github.com/apple/swift-evolution/blob/main/proposals/0299-extend-generic-static-member-lookup.md)) (requires Xcode 13) - [#513](https://github.com/kean/Nuke/pull/513)

```swift
// Before
ImageRequest(url: url, processors: [ImageProcessors.Resize(width: 320)])

// After
ImageRequest(url: url, processors: [.resize(width: 320)])
```

- `ImageRequest` now takes a *non-optional* array of image processors in its initializers. This change is required to mitigate an Xcode issue where it won't suggest code-completion for [SE-0299](https://github.com/apple/swift-evolution/blob/main/proposals/0299-extend-generic-static-member-lookup.md) - [#513](https://github.com/kean/Nuke/pull/513)
- Add `ImageDecoders.Video` (registered by default)

## Nuke 10.4.1

*Aug 30, 2021*

- Fix build on watchOS (needs investigation why xcodebuild returns 0 for failed watchOS builds) - [#505](https://github.com/kean/Nuke/pull/505), thanks to [David Harris](https://github.com/thedavidharris)

## Nuke 10.4.0

*Aug 28, 2021*

- Add an API for efficiently image thumbnails or retrieving existings ones - [#503](https://github.com/kean/Nuke/pull/503)
- Fix an issue with scale (`ImageRequest.UserInfoKey.scaleKey`) not being applied to progressively decoded images

## Nuke 10.3.4

*Aug 26, 2021*

- Fix an issue where if you pass incorrect strings (`String`) in the request, the pipeline eventually start failing silently - [#502](https://github.com/kean/Nuke/pull/502) 

## Nuke 10.3.3

*Aug 18, 2021*

- Fix an issue with disk cache images being overwritten in some scenarios (with disk cache policies that enable encoding and storage of the processed images) - [#500](https://github.com/kean/Nuke/pull/500) 

## Nuke 10.3.2

*Jul 30, 2021*

- Add podspec

## Nuke 10.3.1

*Jul 8, 2021*

- Fix `ImagePublisher` crash with some Combine operators combinations - [#494](https://github.com/kean/Nuke/pull/494), thanks to [Tyler Nickerson](https://github.com/Nickersoft)

## Nuke 10.3.0

*Jun 10, 2021*

- Add `animation` property to `FetchImage` that significantly simplifies how to animate image appearance
- Add `imageType` parameter to `ImageDecoders.Empty`
- Add an option to override image scale (`ImageRequest.UserInfoKey.scaleKey`)

## Nuke 10.2.0

*Jun 6, 2021*

> See also [Nuke 10.0 Release Notes](https://github.com/kean/Nuke/releases/tag/10.0.0)

- `ImageDecoders.Default` now generates previews for GIF
- Add `onSuccess`, `onFailure`, and other callbacks to `FetchImage` 
- Add progressive previews in memory cache support to `FetchImage`
- Add a convenience property with an `ImageContainer` to `FechImage`
- Update `FetchImage` `loadImage()` method that takes publisher to no longer require error to match `ImagePipeline.Error`   
- Add an option to set default processors via `FetchImage`

## Nuke 10.1.0

*Jun 3, 2021*

- Enable progressive decoding by default – it can now be done without sacrificing performance in any meaningful way. To disable it, set `isProgressiveDecodingEnabled` to `false`.
- Enable storing progressively decoding previews in the memory cache by default (`isStoringPreviewsInMemoryCache`)
- Add `isAsynchronous` property to `ImageDecoding` that allows slow decoders (such as custom WebP decoder) to be executed on a dedicated operation queue (the existing `imageDecodingQueue`), while allows fast decoders to be executed synchronously
- Add `entryCostLimit` property to `ImageCache` that specifies the maximum cost of a cache entry in proportion to the `costLimit`. `0.1`, by default.

## Nuke 10.0.1

*Jun 1, 2021*

- Fix watchOS target

## Nuke 10.0

*Jun 1, 2021*

Nuke 10 is extreme in every way. It is faster than the previous version (up to 30% improvement to some operations), more powerful, more ergonomic, and is even easier to learn and use. It brings big additions to the caching infrastructure, great SwiftUI and Combine support, and more ways to adjust the system to fit your needs.

This release is also a massive step-up in the general quality of the framework. It has many improvements to the docs (for example, a complete rewrite of the [caching guide](https://kean.blog/nuke/guides/caching)), more inline comments, more unit tests (Nuke now has ~100% test coverage with 2x number of lines of code in the test target compared to the main target). It's as reliable as it gets.

> **Migration.** The compiler will assist you with the migration, but if something isn't clear, there is a comprehensive [migration guide](https://github.com/kean/Nuke/blob/master/Documentation/Migrations/Nuke%2010%20Migration%20Guide.md) available.
>
> **Switching.** Switching from Kingfisher? There is now a [dedicated guide](https://github.com/kean/Nuke/blob/master/Documentation/Switch/switch-from-kingfisher.md) available to assist you. There is also one for [migrating from SDWebImage](https://github.com/kean/Nuke/blob/master/Documentation/Switch/switch-from-sdwebimage.md).

### Caching

- Add [`DataCachePolicy`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Configuration_DataCachePolicy/) to replace deprecated `DataCacheOptions.storedItems`. The new policy fixes some of the inefficiencies of the previous model and provides more control. For example, one of the additions is an [`.automatic`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Configuration_DataCachePolicy/#imagepipeline.configuration.datacachepolicy.automatic) policy: for requests with processors, encode and store processed images; for requests with no processors, store original image data. You can learn more about the policies and other caching changes in ["Caching: Cache Policy."](https://kean.blog/nuke/guides/caching#cache-policy)
-  Add [`ImagePipeline.Cache`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Cache/) with a whole range of convenience APIs for managing cached images: read, write, remove images from all cache layers.
- Add [`ImagePipeline.Configuration.withDataCache`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Configuration/#imagepipeline.configuration.withdatacache) (aggressive disk cache enabled) and [`withURLCache`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipeline_Configuration/#imagepipeline.configuration.withurlcache) (HTTP disk cache enabled) to make it easier to set up a pipeline with a configuration you want. Learn more in ["Caching: Configuration."](https://kean.blog/nuke/guides/caching#configuration)
- Add `removeAll()` method to `ImageCaching` and `DataCaching` protocols
- Add `containsData(for:)` method to `DataCaching` and `DataCache` which checks if the data exists without bringing it to memory
- Add [`ImageResponse.CacheType`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageResponse_CacheType/) to address [#361](https://github.com/kean/Nuke/issues/361) and [#435](https://github.com/kean/Nuke/issues/435). It defines the source of the retrieved image.
- The pipeline no longer stores images fetched using file:// and data:// schemes in the disk cache
- `ImageCaching` protocols now works with a new [`ImageCacheKey`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageCacheKey/) type (an opaque container) instead of `ImageRequest`. If you are providing a custom implementation of the `ImageCaching` protocol, it needs to be updated. It is now easier because there is no need to come up with a key.

### NukeUI (Beta)

[NukeUI](https://github.com/kean/NukeUI) is a new Swift package. It is a comprehensive solution for displaying lazily loaded images on Apple platforms. 

It uses [Nuke](https://github.com/kean/Nuke) for loading images and has all customization options you can possibly imagine. It also supports animated GIFs rendering thanks to [Gifu](https://github.com/kaishin/Gifu) and caching and displayng short videos as a more efficient alternative to GIF.

The library contains two types:

- `LazyImage` for SwiftUI
- `LazyImageView` for UIKit and AppKit

Both views have an equivalent sets of APIs.

```swift
struct ContainerView: View {
    var body: some View {
        LazyImage(source: "https://example.com/image.jpeg")
            .placeholder { Image("placeholder") }
            .transition(.fadeIn(duration: 0.33))
    }
}
```

### SwiftUI

Nuke now has first-class SwiftUI support with [FetchImage](https://kean.blog/nuke/guides/swiftui) which is now part of the main repo, no need to install it separately. It also has a couple of new additions:

- Add `result` property (previously you could only access the loaded image)
- Add `AnyPublisher` support via a new `func load<P: Publisher>(_ publisher: P) where P.Output == ImageResponse, P.Failure == ImagePipeline.Error` method. You can use it with a custom publisher created by combining publishers introduced in [Nuke 9.6](https://github.com/kean/Nuke/releases/tag/9.6.0).
- Add `ImageRequestConvertible` support

### Combine

Nuke 10 goes all-in on Combine. [`ImagePublisher`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePublisher/) was initially introduced in the previous release, [Nuke 9.6](https://github.com/kean/Nuke/releases/tag/9.6.0), and now Combine is supported across the framework.

- `ImageRequest` now supports Combine Publisher via a new initializer `ImageRequest(id:data:)` where `data` is a `Publisher`. It can be used in a variety of scenarios, for example, loading data using `PhotosKit.
- As mentioned earlier, [`FetchImage`](https://kean-org.github.io/docs/nuke/reference/10.0.0/FetchImage/) now also supports publishers. So when you create a publisher chain, there is now an easy way to display it.

### ImageRequest.Options

Nuke 10 has a reworked [`ImageRequest.Options`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageRequest_Options/) option set replacing removed `ImageRequestOptions`. The name is similar, but the options are slightly different. The new approach has more options while being optimized for performance. `ImageRequest` size in memory reduced from 176 bytes to just 48 bytes (3.7x smaller).

- Deprecate [`ImageRequest.CachePolicy`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageRequest_CachePolicy/) which is now part of the new [`ImageRequest.Options`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageRequest_Options/) option set
- Remove `filteredURL`, you can now pass it using `userInfo` and [`.imageIdKey`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageRequest_UserInfoKey/#imagerequest.userinfokey.imageidkey) key instead. It's a rarely used option, and this is why it is now less visible.
- Remove `cacheKey` and `loadKey` (hopefully, nobody is using it because these weren't really designed properly). You can now use the new methods of [`ImagePipeline.Delegate`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipelineDelegate/) that allows customizing the keys.
- Add more options for granular control over caching and loading. For example, [`ImageRequest.Options`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageRequest_Options/) has a new [`.disableDiskCache`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageRequest_Options/#imagerequest.options.disablediskcache) option.
- Move `userInfo` directly to `ImageRequest`. It's now easier to pass and it allows the framework to perform some additional optimizations.
- `userInfo` now uses [`ImageRequest.UserInfoKey`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageRequest_UserInfoKey/) wrapper for keys replacing `AnyHashable`. The new approach is faster and adds type-safety.

### ImagePipeline.Delegate

- Add [`ImagePipeline.Delegate`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipelineDelegate/) with a variety of advanced per-request customization options that were previously not possible. For example, with [`dataCache(for:pipeline:)`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipelineDelegate/) method you can specify a disk cache for each request. With [`will​Cache(data:​image:​for:​pipeline:​completion:​)`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImagePipelineDelegate/#imagepipelinedelegate.willcache(data:image:for:pipeline:completion:)) you can disable caching per-request or modify the cached data. And there are more.
- Deprecated `ImagePipelineObserving` protocol is now fully covered by `ImagePipeline.Delegate`

### Performance

- `ImageRequest` size in memory reduced from 176 bytes to just 48 bytes (3.7x smaller), which is due to the OptionSet usage and also reordering of properties to take advantage of gaps in memory stride. The size of other types was also reduced, but not as dramatically. For example, `ImageTask` and `ImagePipeline.Configuration` now also take a bit less memory
- Coalescing now supports even more scenarios. For example, setting `ImageRequest` `options` with a cache policy no longer prevents coalescing of data tasks.
- The pipeline now performs memory cache lookup of intermediate (not all processors are applied) progressive image previews and apply the remaining processors on demand
- Extend fast track decoding to the disk cache lookup
- For cache policies that require image encoding, encode decompressed images instead of uncompressed ones

### Nuke Builder

[NukeBuilder](https://github.com/kean/NukeBuilder/) is a package that adds a convenience API for creating image requests inspired by SwiftUI. It was updated with support Nuke 10 and some quality-of-life improvements.

- Rename package to NukeBuilder
- Update to Nuke 10.0
- Add [`ImageRequestConvertible`](https://kean-org.github.io/docs/nuke/reference/10.0.0/ImageRequestConvertible/) support which means it now supports more types: `URLRequest` and `String`
- Add Combine support
- Add `ImagePipeline` typealias for convenience – you only need to import `NukeBuilder` in many cases

### Other

- Increase minimum required Xcode version to 12; no changes to the supported platforms
- New releases now come with a pre-compile XCFramework
- `Nuke.loadImage()` methods now work with optional image requests. If the request is `nil`, it handles the scenario the same way as failure.
- `ImageRequest` now also works with optional `URL`
- `String` now also conforms to `ImageRequestConvertible`, closes [#421](https://github.com/kean/Nuke/issues/421)
- Optional `URL` now also conforms to `ImageRequestConvertible`
- Streamline pipeline callback closures
- Pass failing processor to `ImagePipeline.Error.processingFailed`
- Add type-safe `ImageContainer.UserInfoKey` and `ImageRequest.UserInfoKey`
- Pass additional parameter `Data?` to `nuke_display` (ImageView extensions)
- `ImagePrefetcher` now always sets the priority of the requests to its priority
- `ImagePrefetcher` now works with `ImageRequestConvertible`, adding support for `URLRequest` and `String`
- `ImagePipeline` can now be invalidated with `invalidate()` method

### Deprecations

There are deprecation warnings in place to help guide you through the migration process.

- Deprecate `ImageRequestOptions`, use `ImageRequest.Options` instead (it's not just the name change)
- Deprecate `ImagePipelineObserving`, use `imageTask(_:,didReceiveEvent)` from `ImagePipeline.Delegate` instead
- Rename `isDeduplicationEnabled` to `isTaskCoalescingEnabled`
- Deprecate `animatedImageData` associated object for platform images. Use `data` property of `ImageContainer` instead. `animatedImageData` was initially soft-deprecated in Nuke 9.0.
- Deprecate the default `processors` in `ImagePipeline`; use the new `processors` options in `ImageLoadingOptions` instead
- Deprecate `ImageEncoder` and `ImageDecoder` typealiases.


# Nuke 9

## Nuke 9.6.1

*May 24, 2021*

- Remove some risky `DataLoader` optimizations

## Nuke 9.6.0

*May 2, 2021*

- Add `ImageRequest.CachePolicy.returnCacheDataDontLoad`, [#456](https://github.com/kean/Nuke/pull/456)
- Add `ImagePublisher` (Combine extensions)
- Add a convenience `dataLoadingError` property to `ImagePipeline.Error`
- Remove APIs deprecated in versions 9.0-9.1
- Add a note on [`waitsForConnectivity`](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/2908812-waitsforconnectivity) in [Nuke Docs](https://kean.blog/nuke/guides/performance#auto-retry)
- Add ["Low Data Mode"](https://kean.blog/nuke/guides/combine#low-data-mode) in Nuke Docs

## Nuke 9.5.1

*Apr 28, 2021*

- Update to Xcode 12.5. Fixes [#454](https://github.com/kean/Nuke/issues/454). 

## Nuke 9.5.0

*Apr 3, 2021*

- Add `priority` property to `ImagePrefetcher` which changes the priority of both new and outstanding tasks. By default, `.low`. Use-case: reducing the priority to `.veryLow` when moving to a new screen.
- Further `ImagePrefetcher` performance improvements: one less allocation per request, `ImageRequest` instances are now created in background, reduce closure capture lists, optimize cancellation
- `ImagePrefetcher` now automatically sets the proper request priority even when you start prefetching with`ImageRequest`

## Nuke 9.4.1

*Mar 27, 2021*

- Shorter names for parameters in `loadImage()` and `loadData` methods to improve ImagePipeline APIs ergonomics
- Rename `ImagePreheater` to `ImagePrefetcher` (via deprecation) 
- Rewrite `ImagePrefetcher` documentation

## Nuke 9.4.0

*Mar 26, 2021*

- Reduce the number of context switches in `ImagePrefetcher` and `DataLoader`
- Atomics are back, improves direct `ImagePipeline` usage performance
- Fast-track default decoding operations
- Reduce the number of allocations per task
- Deprecate typealiases for progress and completion closures to improve auto-completion
- You can now toggle `ImagePipeline.Configuration.isSignpostLoggingEnabled` while the app is running and without re-creating the pipeline, [#443](https://github.com/kean/Nuke/issues/443)
- Add convenience `subscript` that takes `URL` to `ImageCaching` protocol as extension

## Nuke 9.3.1

*Mar 21, 2021*

- Fix `DataCache` trim ratio, previously was applying size limit too aggressively.
- Deprecate `DataCache.countLimit`. The default limit is now `Int.max`.
- Move demo project to a [separate repo](https://github.com/kean/NukeDemo). Fixes [#442](https://github.com/kean/Nuke/issues/442).

## Nuke 9.3.0

*Feb 22, 2021*

- Improve ImagePipeline background performance by **~40%** (measuring after taking out system calls)
- Reduce number of allocations per task
- Improve Task infrastructure, make ImagePipeline vastly easier to read and understand
- Add more performance and unit tests. Tests are now clocking at 6000 lines of code.
- Add infrastructure for automated memory management testing

## Nuke 9.2.4

*Jan 16, 2021*

- Add support for image orientation in `ImageProcessors.Resize` - [#429](https://github.com/kean/Nuke/pull/429)

## Nuke 9.2.3

*Dec 30, 2020*

- Fix regression introduced in Nuke 9.2.1 where some image processors would not render transparent background correctly - [#424](https://github.com/kean/Nuke/issues/424)

## Nuke 9.2.2

*Dec 26, 2020*

- Deprecate `crop` parameter in `ImageProcessors.Resize` `init(height:)` and `init(width:)` initializers (crop doesn't make sense in with these parameters)

## Nuke 9.2.1

*Dec 15, 2020*

- Fix `CGBitmapContextCreate: unsupported parameter combination` warnings - [#416](https://github.com/kean/Nuke/issues/416)

## Nuke 9.2.0

*Nov 28, 2020*

### Additions

- Add an option to remove an image from all cache layers `pipeline.removeCachedImage(for:)`
- Add `ImageRequest.CachePolicy` to `ImageRequest`. Use `.reloadIgnoringCachedData` to reload the image ignoring all cached data - [#411](https://github.com/kean/Nuke/pull/411)
- Add support for extended color spaces - [#408](https://github.com/kean/Nuke/pull/408)
- Add `ImageProcessors.Circle` and `ImageProcessors.RoundedCorners` on macOS - [#410](https://github.com/kean/Nuke/pull/410)
- Add `ImageProcessors.CoreImage` and `ImageProcessors.GaussianBlur` on macOS - [#413](https://github.com/kean/Nuke/pull/413)
- Add  `ImageType.webp`. WebP is natively supported by the latest Apple platforms - [#412](https://github.com/kean/Nuke/pull/412)

### Improvements

- Introduce `ImageRequestConvertible` protocol to narrow the number of public APIs. For example, if you type `ImagePipeline.shared.loadImage...`, it's now going to suggest twice fewer options.
- Remove `Image` typealias deprecated in Nuke 8.4
- Remove public `CGSize: Hashable` conformance - [#410](https://github.com/kean/Nuke/pull/410)
- Decompression and resizing now preserve image color space and other parameters. For example, grayscale images with 8 bits per component stay images with 8 bits per component.
- Switch from Travis to GitHub Actions - [#409](https://github.com/kean/Nuke/pull/409)
- Fix "Backward matching of the unlabeled trailing closure is deprecated"  warnings

## Nuke 9.1.3

*Nov 17, 2020*

- Fix an issue where HTTP range for resumable requests would sometimes be sent incorrectly - [#389](https://github.com/kean/Nuke/issues/389)
- Fix compile time warnings in Xcode 12

## Nuke 9.1.2

*Aug 25, 2020*

- Fix an issue with `ImageCache` memory pressure monitoring where it was clearing it when memory pressure changes to `normal` level - [#392](https://github.com/kean/Nuke/pull/392) by [Eric Jensen](https://github.com/ejensen)

## Nuke 9.1.1

*June 19, 2020*

### Fixes

- Fix how `RateLimiter` clamps the delay – [#374](https://github.com/kean/Nuke/pull/374) by [Tangent](https://github.com/TangentW)
- Fix an issue where `ImageTask` would stay in memory indefinitely in certain situations - [#377](https://github.com/kean/Nuke/pull/377) by [Ken Bongort](https://github.com/ken-broadsheet)
- Fix an issue in a demo project where "Rate Limiter" demo would use incorrect cell size on first draw 

## Nuke 9.1

*June 1, 2020*

### Enhancements

- `ImageCache` now uses `DispatchSourceMemoryPressure` instead `UIApplication.didReceiveMemoryWarningNotification` to improve watchOS support - [#370](https://github.com/kean/Nuke/pull/370), by [Dennis Oberhoff](https://github.com/docterd)
- Add `tintColor` option to `ImageLoadingOptions` - [#371](https://github.com/kean/Nuke/pull/371) by [Basem Emara](https://github.com/basememara)
- Minor documentation fixes and improvements

## Nuke 9.0

*May 20, 2020*

**Nuke 9** is the best release so far with refinements across the entire framework and some exciting new additions.

> **SwiftUI** · **Combine** · **Task builder API** · **New advanced set of core protocols for power-users** · **HEIF** · **Transcoding images in disk cache** · **Progressive decoding performance improvements** · **Improved resizing APIs** · **Automatic registering of decoders** · **SVG** · **And More**

Most of the Nuke APIs are source compatible with Nuke 8. There is also a [Nuke 9 Migration Guide](https://github.com/kean/Nuke/blob/9.0.0/Documentation/Migrations/Nuke%209%20Migration%20Guide.md) to help with migration.

### Overview

The primary focus of this release was to build on top the infrastructure introduced in Nuke 8 to deliver more **advanced features** while keeping the easy things easy. To achieve this, in Nuke 9, all core protocols, like `ImageProcessing`, `ImageEncoding`, `ImageDecoding`, now have a  basic subset of methods that you _must_ implement, and then there are new _advanced_ methods which are optional and give you full control over the pipeline.

Along with Nuke 9, **three new amazing Swift packages** were introduced:

- [**FetchImage**](https://github.com/kean/FetchImage) which makes it easy to use Nuke with SwiftUI
- [**ImagePublisher**](https://github.com/kean/ImagePublisher) with Combine publishers for Nuke
- And finally [**ImageTaskBuilder**](https://github.com/kean/ImageTaskBuilder) which introduces a new fun and convenient way to use Nuke. I really love this package. Just look at these APIs:

```swift
ImagePipeline.shared.image(with: URL(string: "https://")!)
    .resize(width: 320)
    .blur(radius: 10)
    .priority(.high)
    .load { result in
        print(result)
    }
```

I would also like to highlight a few other changes to **improve documentation**.

First, there is a completely new [**API Reference**](https://kean-org.github.io/docs/nuke/reference/9.0.0/) available generated using [SwiftDoc](https://github.com/SwiftDocOrg/swift-doc), a new package for generating documentation for Swift projects.

There is a completely new [**README**](https://github.com/kean/Nuke/tree/9.0.0) and two new guides:

- [**Image Pipeline Guide**](https://github.com/kean/Nuke/blob/9.0.0/Documentation/Guides/image-pipeline.md) with a detailed description of how the pipeline delivers images
- [**Image Formats Guide**](https://github.com/kean/Nuke/blob/9.0.0/Documentation/Guides/image-formats.md) with an overview of the improved decoding/encoding infrastructure and information how to support variety of image formats: GIF, HEIF, SVG, WeP, and more.

There is also a new [**Troubleshooting Guide**](https://github.com/kean/Nuke/blob/9.0.0/Documentation/Guides/troubleshooting.md).

Another small but delightful change the demo project which can now be run by simply clicking on the project and running it, all thanks to Swift Package Manager magic.

### Changelog

#### General Improvements

- Bump minimum platform version requirements. The minimum iOS version is now iOS 11 which is a 64-bit only system. This is great news if you are installing your dependencies using Carthage as Nuke is now going to compile twice as fast: no need to compile for `i386` and `armv7` anymore.

#### Documentation Improvements

- Rewrite most of the README
- Add a completely new [**API Reference**](https://kean-org.github.io/docs/nuke/reference/9.0.0/) available generated using [SwiftDoc](https://github.com/SwiftDocOrg/swift-doc), a new package for generating documentation for Swift projects
- Add a completely new [**Image Pipeline Guide**](https://github.com/kean/Nuke/blob/9.0.0/Documentation/Guides/image-pipeline.md) which describes in detail how the pipeline works.
- Add a new [**Image Formats Guide**](https://github.com/kean/Nuke/blob/9.0.0/Documentation/Guides/image-formats.md)

#### `ImageProcessing` improvements

There are now two levels of image processing APIs. For the basic processing needs, implement the following method:

```swift
func process(_ image: UIImage) -> UIImage? // NSImage on macOS
```

If your processor needs to manipulate image metadata (`ImageContainer`), or get access to more information via the context (`ImageProcessingContext`), there is now an additional method that allows you to do that:

 ```swift
func process(_ container: ImageContainer, context: ImageProcessingContext) -> ImageContainer?
```

- All image processors are now available `ImageProcessors` namespace so it is now easier to find the ones you are looking for. Unrelated types were moved to `ImageProcessingOption`.
- Add `ImageResponse` to `ImageProcessingContext`
- New convenience `ImageProcessors.Resize.init(width:)` and `ImageProcessors.Resize.init(height:)` initializers

#### `ImageDecoding` Improvements

- Add a new way to register the decoders in `ImageDecoderRegistry` with `ImageDecoderRegistering` protocol. `public func register<Decoder: ImageDecoderRegistering>(_ decoder: Decoder.Type)` - [#354](https://github.com/kean/Nuke/pull/354)

```swift
/// An image decoder which supports automatically registering in the decoder register.
public protocol ImageDecoderRegistering: ImageDecoding {
    init?(data: Data, context: ImageDecodingContext)
    // Optional
    init?(partiallyDownloadedData data: Data, context: ImageDecodingContext)
}
```

- The default decoder now implements `ImageDecoderRegistering` protocol
- Update the way decoders are created. Now if the decoder registry can't create a decoder for the partially downloaded data, the pipeline will no longer create (failing) decoding operation reducing the pressure on the decoding queue
- Rework `ImageDecoding` protocol
- Nuke now supports decompression and processing of images that require image data to work
- Deprecate `ImageResponse.scanNumber`, the scan number is now passed in `ImageContainer.userInfo[ImageDecodert.scanNumberKey]` (this is a format-specific feature and that's why I made it non-type safe and somewhat hidden). Previously, it was also only working for the default `ImageDecoders.Default`. Now any decoder can pass scan number, or any other information using `ImageContainer.userInfo`
- All decoders are now defined in `ImageDecoders` namespace
- Add `ImageDecoders.Empty`
- Add `ImageType` struct 

#### `ImageEncoding` Improvements

[#353](https://github.com/kean/Nuke/pull/353) - There are now two levels of image encoding APIs. For the basic encoding needs, implement the following method:

```swift
func encode(_ image: UIImage) -> UIImage? // NSImage on macOS
```

If your encoders needs to manipulate image metadata (`ImageContainer`), or get access to more information via the context (`ImageEncodingContext`), there is now an additional method that allows you to do that:

 ```swift
func encode(_ container: ImageContainer, context: ImageEncodingContext) -> Data?
```

- All image encoders are now available `ImageEncoders` namespace so it is now easier to find the ones you are looking for.
- Add `ImageEncoders.ImageIO` with HEIF support - [#344](https://github.com/kean/Nuke/pull/344)
- The default adaptive encoder now uses `ImageEncoders.ImageIO` under the hood and can be configured to support HEIF

#### Progressive Decoding Improvements

- You can now opt-in to store progressively generated previews in the memory cache by setting the pipeline option `isStoringPreviewsInMemoryCache` to `true`. All of the previews have `isPreview` flag set to `true`. - [$352](https://github.com/kean/Nuke/pull/352)

#### Improved Cache For Processed Images - [#345](https://github.com/kean/Nuke/pull/345)

Nuke 9 revisits data cache for processed images feature introduced in [Nuke 8.0](https://github.com/kean/Nuke/releases/tag/8.0) and fixes all the rough edges around it.

There are two primary changes.

#### 1. Deprecate `isDataCachingForOriginalImageDataEnabled` and `isDataCachingForProcessedImagesEnabled` properties.

These properties were replaced with a new `DataCacheOptions`.

```swift
public struct DataCacheOptions {
    /// Specifies which content to store in the `dataCache`. By default, the
    /// pipeline only stores the original image data downloaded using `dataLoader`.
    /// It can be configured to encode and store processed images instead.
    ///
    /// - note: If you are creating multiple versions of the same image using
    /// different processors, it might be worse enabling both `.originalData`
    /// and `.encodedImages` cache to reuse the same downloaded data.
    ///
    /// - note: It might be worth enabling `.encodedImages` if you want to
    /// transcode downloaded images into a more efficient format, like HEIF.
    public var storedItems: Set<DataCacheItem> = [.originalImageData]
}

public enum DataCacheItem {
    /// Original image data.
    case originalImageData
    /// Final image with all processors applied.
    case finalImage
}
```

Now we no longer rely on documentation to make sure that you disable data cache for original image data when you decide to cache processed images instead.

#### 2. Rework `DataCacheItem.finalImage` behavior.

The primary reason for deprecation is a significantly changed behavior of data cache for processed images.

The initial version introduced back in Nuke 8.0 never really made sense. For example, only images for requests with processors were stored, but not the ones without. You can see how this could be a problem, especially if you disable data cache for original image data which was a recommended option.

The new behavior is much simpler. You set `configuration.dataCacheOptions.storedItems` to `[. finalImage]`, and Nuke encodes and stores all of the downloaded images, regardless of whether they were processed or not.

#### `DataCache` Improvements - [#350](https://github.com/kean/Nuke/pull/350)

Nuke 9 realized the original vision for `DataCache`. The updated staging/flushing mechanism now performs flushes on certain intervals instead of on every write. This makes some of the new `DataCache` features possible.

- `flush` not performs synchronously
- Add `flush(for:)` methods which allows to flush changes on disk only for the given key
- Add public property `let queue: DispatchQueue`
- Add public method `func url(for key: Key) -> URL?`

#### `ImageContainer`

This release introduces `ImageContainer` type. It is integrated throughout the framework instead of `PlatformImage`.

**Reasoning**

- Separate responsibility. `ImageResponse` - result of the current request with information about the current request, e.g. `URLResponse` that was received. `ImageContainer` - the actual downloaded and processed image regardless of the request
- Stop relying on Objective-C runtime which `animatedImageData` was using
- Stop relying on extending Objective-C classes like `UIImage`
- Add type-safe way to attach additional information to downloaded images

**Changes**

- Update `ImageCaching` protocol to store `ImageContainer` instead of `ImageResponse`. `ImageResponse` is a result of the individual request, it should not be saved in caches.

```swift
public protocol ImageCaching: AnyObject {
    subscript(request: ImageRequest) -> ImageContainer?
}
```

- Update `ImagePipeline.cachedImage(for:)` method to return `ImageContainer`
- Deprecate `PlatformImage.animatedImageData`, please use `ImageContainer.data` instead
- Deprecated `ImagePipelineConfiguration.isAnimatedImageDataEnabled`, the default `ImageDecoder` now set `ImageContainer.data` automatically when it recognizes GIF format

#### Other

- `ImagePreheater` now automatically cancels all of the outstanding tasks on deinit - [#349](https://github.com/kean/Nuke/pull/349)
- `ImagePipeline` now has `func cacheKey(for request: ImageRequest, item: DataCacheItem) -> String` method which return a key for disk cache
- Change the type of `ImageRequest.userInfo` from `Any?` to `[AnyHashable: Any]`
- Remove `DFCache` from demo - [#347](https://github.com/kean/Nuke/pull/347)
- Remove `FLAnimatedImage` and Carthage usage from demo - [#348](https://github.com/kean/Nuke/pull/348)
- Migrate to Swift 5.1 - [#351](https://github.com/kean/Nuke/pull/351)
- Add `ImageType.init(data:)`
- Add `ImageLoadingOptions.isProgressiveRenderingEnabled`
- Add public `ImageContainer.map`
- Add "Rendering Engines" section in image-formats.md
- `ImageDecoder` now attaches `ImageType` to the image
- `ImageProcessingOptions.Border` now accepts unit as a parameter

### Fixes

- Fix how `ImageProcesors.Resize` compares size when different units are used
- Fix an issue with `ImageProcessors.Resize` String identifier being equal with different content modes provided
- Fix TSan warnings - [#365](https://github.com/kean/Nuke/pull/365), by [Luciano Almeida](https://github.com/LucianoPAlmeida)


# Nuke 8

## Nuke 8.4.1

*March 19, 2020*

- Podspec now explicitly specifies supported Swift versions - [340](https://github.com/kean/Nuke/pull/340), [Richard Lee](https://github.com/dlackty)
- Fix a memory leak when the URLSession wasn't deallocated correctly - [336](https://github.com/kean/Nuke/issues/336)

### Announcements

There are two new Swift packages available in Nuke ecosystem:

- [**FetchImage**](https://github.com/kean/FetchImage) that makes it easy to download images using Nuke and display them in SwiftUI apps. One of the notable features of `FetchImage` is support for iOS 13 Low Data mode.
- [**ImagePublisher**](https://github.com/kean/ImagePublisher) that provides [Combine](https://developer.apple.com/documentation/combine) publishers for some of the Nuke APIs.

Both are distributed exclusively via [Swift Package Manager](https://swift.org/package-manager/). And both are API _previews_. Please, try them out, and feel free to [contact me](https://twitter.com/a_grebenyuk) with any feedback that you have. 


## Nuke 8.4.0

*November 17, 2019*

- Fix an issue with `RoundedCorners` image processor not respecting the `Border` parameter – [327](https://github.com/kean/Nuke/pull/327), [Eric Jensen](https://github.com/ejensen)
- Add an optional `border` parameter to the `Circle` processor – [327](https://github.com/kean/Nuke/pull/327), [Eric Jensen](https://github.com/ejensen)
- Add `ImagePipelineObserving` and `DataLoaderObserving` protocols to allow users to tap into the internal events of the subsystems to enable logging and other features – [322](https://github.com/kean/Nuke/pull/322)
- Deprecate `Nuke.Image` to avoid name clashes with `SwiftUI.Image` in the future , add `PlatformImage` instead – [321](https://github.com/kean/Nuke/pull/321) 
- Make `ImagePipeline` more readable – [320](https://github.com/kean/Nuke/pull/320)
- Update demo project to use Swift Package Manager instead of CocoaPods – [319](https://github.com/kean/Nuke/pull/319)

## Nuke 8.3.1

*October 26, 2019*

- Add dark mode support to the demo project – [#307](https://github.com/kean/Nuke/pull/307), [Li Yu](https://github.com/yurited)

## Nuke 8.3.0

*October 06, 2019*
 
 - Add `processors` option to `ImagePipeline.Configuration`  – [300](https://github.com/kean/Nuke/pull/300), [Alessandro Vendruscolo](https://github.com/vendruscolo)
 - Add `queue` option to `loadImage` and `loadData` methods of `ImagePipeline` – [304](https://github.com/kean/Nuke/pull/304)
 - Add `callbackQueue` option to `ImagePipeline.Configuration` – [304](https://github.com/kean/Nuke/pull/304)


## Nuke 8.2.0

*September 20, 2019*

- Add support for Mac Catalyst – [#299](https://github.com/kean/Nuke/pull/299), [Jonathan Downing](https://github.com/JonathanDowning)


## Nuke 8.1.1

*September 1, 2019*

- Switch to a versioning scheme which is compatible with Swift Package Manager


## Nuke 8.1

*August 25, 2019*

- Configure dispatch queues with proper QoS – [#291](https://github.com/kean/Nuke/pull/291), [Michael Nisi](https://github.com/michaelnisi)
- Remove synchronization points in `ImageDecoder` which is not needed starting from iOS 10 – [#277](https://github.com/kean/Nuke/pull/277)
- Add Swift Package Manager to Installation Guides
- Improve Travis CI setup: run tests on multiple Xcode versions, run thread safety tests, run SwiftLint validations, build demo project, validate Swift package – [#279](https://github.com/kean/Nuke/pull/279), [#280](https://github.com/kean/Nuke/pull/280), [#281](https://github.com/kean/Nuke/pull/281), [#284](https://github.com/kean/Nuke/pull/284), [#285](https://github.com/kean/Nuke/pull/285)


## Nuke 8.0.1

*July 21, 2019*

- Remove synchronization in `ImageDecoder` which is no longer needed – [#277](https://github.com/kean/Nuke/issues/277)


## Nuke 8.0

*July 8, 2019*

Nuke 8 is the most powerful, performant, and refined release yet. It contains major advancements it some areas and brings some great new features. One of the highlights of this release is the documentation which was rewritten from the ground up.

> **Cache processed images on disk** · **New built-in image processors** · **ImagePipeline v2** · **Up to 30% faster main thread performance** · **`Result` type** · **Improved deduplication** · **`os_signpost` integration** · **Refined ImageRequest API** · **Smart decompression** · **Entirely new documentation**

Most of the Nuke APIs are source compatible with Nuke 7. There is also a [Nuke 8 Migration Guide](https://github.com/kean/Nuke/blob/8.0/Documentation/Migrations/Nuke%208%20Migration%20Guide.md) to help with migration.

### Image Processing

#### [#227 Cache Processed Images on Disk](https://github.com/kean/Nuke/pull/227)

`ImagePipeline` now supports caching of processed images on disk. To enable this feature set `isDataCacheForProcessedDataEnabled` to `true` in the pipeline configuration and provide a `dataCache`. You can use a built-in `DataCache` introduced in [Nuke 7.3](https://github.com/kean/Nuke/releases/tag/7.3) or write a custom one.

Image cache can significantly improve the user experience in the apps that use heavy image processors like Gaussian Blur.

#### [#243 New Image Processors](https://github.com/kean/Nuke/pull/243)

Nuke now ships with a bunch of built-in image processors including:

-  `ImageProcessor.Resize`
-  `ImageProcessor.RoundedCorners`
-  `ImageProcessor.Circle`
-  `ImageProcessor.GaussianBlur`
-  `ImageProcessor.CoreImageFilter`

There are also `ImageProcessor.Anonymous` to create one-off processors from closures and `ImageProcessor.Composition` to combine two or more processors.

#### [#245 Simplified Processing API](https://github.com/kean/Nuke/pull/245)

Previously Nuke offered multiple different ways to add processors to the request. Now there is only one, which is also better than all of the previous versions:

```swift
let request = ImageRequest(
    url: URL(string: "http://..."),
    processors: [
        ImageProcessor.Resize(size: CGSize(width: 44, height: 44), crop: true),
        ImageProcessor.RoundedCorners(radius: 16)
    ]
)
```

> Processors can also be set using a respective mutable `processors` property.

> Notice that `AnyImageProcessor` is gone! You can simply use `ImageProcessing` protocol directly in places where previously you had to use a type-erased version.


#### [#229 Smart Decompression](https://github.com/kean/Nuke/pull/229)

In the previous versions, decompression was part of the processing API and `ImageDecompressor` was the default processor set for each image request. This was mostly done to simplify implementation but it was confusing for the users.

In the new version, decompression runs automatically and it no longer a "processor". The new decompression is also _smarter_. It runs only when needed – when we know that image is still in a compressed format and wasn't decompressed by one of the image processors.

Decompression runs on a new separate `imageDecompressingQueue`. To disable decompression you can set a new `isDecompressionEnabled` pipeline configuration option to `false`.

#### [#247 Avoiding Duplicated Work when Applying Processors](https://github.com/kean/Nuke/pull/247)

The pipeline avoids doing any duplicated work when loading images. Now it also avoids applying the same processors more than once. For example, let's take these two requests:

```swift
let url = URL(string: "http://example.com/image")
pipeline.loadImage(with: ImageRequest(url: url, processors: [
    ImageProcessor.Resize(size: CGSize(width: 44, height: 44)),
    ImageProcessor.GaussianBlur(radius: 8)
]))
pipeline.loadImage(with: ImageRequest(url: url, processors: [
    ImageProcessor.Resize(size: CGSize(width: 44, height: 44))
]))
```

Nuke will load the image data only once, resize the image once and apply the blur also only once. There is no duplicated work done at any stage. If any of the intermediate results are available in the data cache, they will be used.

### ImagePipeline v2

Nuke 8 introduced a [major new iteration](https://github.com/kean/Nuke/pull/235) of the `ImagePipeline` class. The class was introduced in Nuke 7 and it contained a lot of incidental complexity due to addition of progressive decoding and some other new features. In Nuke 8 it was rewritten to fully embrace progressive decoding. The new pipeline is smaller, simpler, easier to maintain, and more reliable.

It is also faster.

#### +30% Main Thread Performance

The image pipeline spends even less time on the main thread than any of the previous versions. It's up to 30% faster than Nuke 7.

#### [#239 Load Image Data](https://github.com/kean/Nuke/pull/239)

Add a new `ImagePipeline` method to fetch original image data:

```swift
@discardableResult
public func loadData(with request: ImageRequest,
                     progress: ((_ completed: Int64, _ total: Int64) -> Void)? = nil,
                     completion: @escaping (Result<(data: Data, response: URLResponse?), ImagePipeline.Error>) -> Void) -> ImageTask
```

This method now powers `ImagePreheater` with destination `.diskCache` introduced in [Nuke 7.4](https://github.com/kean/Nuke/releases/tag/7.4) (previously it was powered by a hacky internal API).

#### [#245 Improved ImageRequest API](https://github.com/kean/Nuke/pull/245)

The rarely used options were extracted into the new `ImageRequestOptions` struct and the request initializer can now be used to customize _all_ of the request parameters.

#### [#255 `filteredURL`](https://github.com/kean/Nuke/pull/255)

You can now provide a `filteredURL` to be used as a key for caching in case the URL contains transient query parameters:

```swift
let request = ImageRequest(
    url: URL(string: "http://example.com/image.jpeg?token=123")!,
    options: ImageRequestOptions(
        filteredURL: "http://example.com/image.jpeg"
    )
)
```

#### [#241 Adopt `Result` type](https://github.com/kean/Nuke/pull/241)

Adopt the `Result` type introduced in Swift 5. So instead of having a separate `response` and `error` parameters, the completion closure now has only one parameter - `result`.

```swift
public typealias Completion = (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void
```

### Performance

Apart from the general performance improvements Nuke now also offers a great way to measure performance and gain visibility into how the system behaves when loading images.

#### [#250 Integrate `os_signpost`](https://github.com/kean/Nuke/pull/250)

Integrate [os_signpost](https://developer.apple.com/documentation/os/logging) logs for measuring performance. To enable the logs set `ImagePipeline.Configuration.isSignpostLoggingEnabled` (static property) to `true` before accessing the `shared` pipeline.

With these logs, you have visibility into the image pipeline. For more information see [WWDC 2018: Measuring Performance Using Logging](https://developer.apple.com/videos/play/wwdc2018/405/) which explains `os_signpost` in a great detail.

<img width="1375" alt="Screenshot 2019-06-01 at 10 46 52" src="https://user-images.githubusercontent.com/1567433/58753519-8adf7b80-84c0-11e9-806a-eac24ddaa2dd.png">

### Documentation

All the documentation for Nuke was rewritten from scratch in Nuke 8. It's now more concise, clear, and it even features some fantastic illustrations:

<img width="1158" alt="Screenshot 2019-06-11 at 22 31 18" src="https://user-images.githubusercontent.com/1567433/59304491-aacd2700-8c98-11e9-9630-293d27545b1a.png">

The screenshots come the the **reworked demo** project. It gained new demos including *Image Processing* demo and also a way to change `ImagePipeline` configuration in runtime.

### Misc

- Add a cleaner way to set `ImageTask` priority using a new `priority` property – [#251](https://github.com/kean/Nuke/pull/251)
- [macOS] Implement image cost calculation for `ImageCache` – [#236](https://github.com/kean/Nuke/issues/236)
- [watchOS] Add `WKInterfaceImage` support
- Future-proof Objective-C `ImageDisplaying` protocol by adding `nuke_` prefixes to avoid clashes in Objective-C runtime
- Add convenience `func decode(data: Data) -> Image?` method with a default `isFinal` argument to `ImageDecoding` protocol – [e3ca5e](https://github.com/kean/Nuke/commit/e3ca5e646ddc1939d05a121de20cf88e2c8220cc)
- Add convenience `func process(image: Image) -> Image?` method to `ImageProcessing` protocol
- `DataCache` will now automatically re-create its root directory if it was deleted underneath it
- Add public `flush` method to `DataCache` 


# Nuke 7

## Nuke 7.6.3

*May 1, 2019*

- Fix [#226](https://github.com/kean/Nuke/issues/226) `ImageTask.setPriority(_:)` sometimes crashes


## Nuke 7.6.2

*Apr 24, 2019*

- Fix [Thread Sanitizer warnings](https://github.com/kean/Nuke/issues/224). The issue was related to `unfair_lock` usage which was introduced as a replacement for `OSAtomic` functions in Nuke 7.6. In order to fix the issue, `unfair_lock` was replaced with simple `NSLock`. The performance hit is pretty insignificant and definitely isn't worth introducing this additional level of complexity.

## Nuke 7.6.1

*Apr 13, 2019*

- Fix SwiftPM 5.0 support by adding explicit platform version requirements  – [Vadim Shpakovski](https://github.com/shpakovski) in [#220](https://github.com/kean/Nuke/pull/220)
- Update [Nuke 7 Migration Guide](https://github.com/kean/Nuke/blob/7.6.1/Documentation/Migrations/Nuke%207%20Migration%20Guide.md)


## Nuke 7.6

*Apr 7, 2019*

- Add Swift 5.0 support – [Daniel Storm](https://github.com/DanielStormApps) in [#217](https://github.com/kean/Nuke/pull/217)
- Add SwiftPM 5.0 support – [Vadim Shpakovski](https://github.com/shpakovski) in [#219](https://github.com/kean/Nuke/pull/219)
- Remove Swift 4.0 and Swift 4.1 support
- Remove iOS 9, tvOS 9, watchOS 2.0, macOS 10.10 and macOS 10.11 support
- Add a single `Nuke` target which can build the framework for any platform
- Replace deprecated `OSAtomic` functions with `unfair_lock`, there are no performance regressions


## Nuke 7.5.2

*Dec 26, 2018*

- [macOS] Fix `Nuke.loadImage` image is not displayed when `.fadeIn` transition is used – [#206](https://github.com/kean/Nuke/issues/206)
- Add `.alwaysTransition` flag to `ImageLoadingOptions` – [@gabzsa](https://github.com/gabzsa) in [#201](https://github.com/kean/Nuke/pull/201)


## Nuke 7.5.1

*Nov 8, 2018*

- Update Swift version in pbxproj to Swift 4.2, [#199](https://github.com/kean/Nuke/issues/199)
- Update demo to Swift 4.2


## Nuke 7.5

*Oct 21, 2018*

### Additions

- [#193](https://github.com/kean/Nuke/pull/193) Add an option to `ImageDecompressor` to allow images to upscale, thanks to [@drkibitz](https://github.com/drkibitz)
- [#197](https://github.com/kean/Nuke/pull/197) Add a convenience initializer to `ImageRequest` which takes an image processor (`ImageProcessing`) as a parameter, thanks to [@drkibitz](https://github.com/drkibitz)

### Improvements

- Add a guarantee that if you cancel `ImageTask` on the main thread, you won't receive any more callbacks (progress, completion)
- Improve internal `Operation` performance, images are loading up to 5% faster

### Removals

Nuke 7 had a lot of API changes, to make the migration easier it shipped with Deprecated.swift file (536 line of code) which enabled Nuke 7 to be almost 100% source-compatible with Nuke 6. It's been 6 months since Nuke 7 release, so now it's finally a good time to remove all of this code. 


## Nuke 7.4.2

*Oct 1, 2018*

- #174 Fix an issue with an `ImageView` reuse logic where in rare cases a wrong image would be displayed, thanks to @michaelnisi


## Nuke 7.4.1

*Sep 25, 2018*

- Disable automatic `stopPreheating` which was causing some issues


## Nuke 7.4

*Sep 22, 2018*

### Prefetching Improvements

- Add an `ImagePreheater.Destination` option to `ImagePreheater`. The default option is `.memoryCache` which works exactly the way `ImagePreheater` used to work before. The more interesting option is `.diskCache`. The preheater with `.diskCache` destination will skip image data decoding entirely to reduce CPU and memory usage. It will still load the image data and store it in disk caches to be used later.
- Add convenience `func startPreheating(with urls: [URL])` function which creates requests with `.low` requests for you.
- `ImagePreheater` now automatically cancels all of the managed outstanding requests on deinit.
- Add `UICollectionViewDataSourcePrefetching` demo on iOS 10+. Nuke still supports iOS 9 so [Preheat](https://github.com/kean/Preheat) is also still around.

### Other Changes

- #187 Fix an issue with progress handler reporting incorrect progress for resumed (206 Partial Content) downloads
- Remove `enableExperimentalAggressiveDiskCaching` function from `ImagePipeline.Configuration`, please use `DataCache` directly instead
- Update [Performance Guide](https://github.com/kean/Nuke/blob/7.4/Documentation/Guides/Performance%20Guide.md)


## Nuke 7.3.2

*Jul 29, 2018*

- #178 Fix TSan warning being triggered by performance optimization in `ImageTask.cancel()` (false positive)
- Fix an issue where a request (`ImageRequest`) with a default processor and a request with the same processor but set manually would have different cache keys 

## Nuke 7.3.1

*Jul 20, 2018*

- `ImagePipeline` now updates the priority of shared operations when the registered tasks get canceled (was previously only reacting to added tasks)
- Fix an issue where `didFinishCollectingMetrics` closure wasn't called for the tasks completed with images found in memory cache and the tasks canceled before they got a chance to run. Now _every_ created tasks gets a corresponding `didFinishCollectingMetrics` call.


## Nuke 7.3

*Jun 29, 2018*

This release introduces new `DataCache` type and features some other improvements in custom data caching.

- Add new `DataCache` type - a cache backed by a local storage with an LRU cleanup policy. This type is a reworked version of the experimental data cache which was added in Nuke 7.0. It's now much simpler and also faster. It allows for reading and writing in parallel, it has a simple consistent API, and I hope it's going to be a please to use.

> **Migration note:** The storage format - which is simply a bunch of files in a directory really - is backward compatible with the previous implementation. If you'd like the new cache to continue working with the same path, please create it with "com.github.kean.Nuke.DataCache" name and use the same filename generator that you were using before:
> 
>    try? DataCache(name: "com.github.kean.Nuke.DataCache", filenameGenerator: filenameGenerator)

- #160 `DataCache` now has a default `FilenameGenerator` on Swift 4.2 which uses `SHA1` hash function provided by `CommonCrypto` (`CommonCrypto` is not available on the previous version of Swift).

- #171 Fix a regression introduced in version 7.1. where experimental `DataCache` would not perform LRU data sweeps.

- Update `DataCaching` protocol. To store data you now need to implement a synchronous method `func cachedData(for key: String) -> Data?`. This change was necessary to make the data cache fit nicely in `ImagePipeline` infrastructure where each stage is managed by a separate `OperationQueue` and each operation respects the priority of the image requests associated with it.

- Add `dataCachingQueue` parameter to `ImagePipeline.Configuration`. The default `maxConcurrentOperationCount` is `2`.

- Improve internal `Operation` type performance.


## Nuke 7.2.1

*Jun 18, 2018*

Nuke's [roadmap](https://trello.com/b/Us4rHryT/nuke) is now publicly available. Please feel free to contribute!

This update addresses tech debt introduces in version 7.1 and 7.2. All of the changes made in these version which improved deduplication are prerequisites for implementing smart prefetching which be able to skip decoding, load to data cache only, etc.

### Enhancements

- Simpler and more efficient model for managing decoding and processing operations (including progressive ones). All operations now take the request priority into account. The processing operations are now created per processor, not per image loading session which leads to better performance.
- When subscribing to existing session which already started processing, pipeline will try to find existing processing operation.
- Update `DFCache` integration demo to use new `DataCaching` protocol
- Added ["Default Image Pipeline"](https://github.com/kean/Nuke#default-image-pipeline) section and ["Image Pipeline Overview"](https://github.com/kean/Nuke#image-pipeline-overview) sections in README.
- Update "Third Party Libraries" guide to use new `DataCaching` protocol


## Nuke 7.2

*Jun 12, 2018*

### Additions

- #163 Add `DataCaching` protocol which can be used to implement custom data cache. It's not documented yet, the documentation going to be updated in 7.2.1.

### Improvements

- Initial iOS 12.0, Swift 4.2 and Xcode 10 beta 1 support
- #167 `ImagePipeline` now uses `OperationQueue` instead of `DispatchQueue` for decoding images. The queue now respects `ImageRequest` priority. If the task is cancelled the operation added to a queue is also cancelled. The queue can be configured via `ImagePipeline.Configuration`.
- #167 `ImagePipeline` now updates processing operations' priority.

### Fixes

- Fix a regression where in certain deduplication scenarios a wrong image would be saved in memory cache
- Fix MP4 demo project
- Improve test coverage, bring back `DataCache` (internal) tests


## Nuke 7.1

*May 27, 2018*

### Improvements

- Improve deduplication. Now when creating two requests (at roughly the same time) for the same images but with two different processors, the original image is going to be downloaded once (used to be twice in the previous implementation) and then two separate processors are going to be applied (if the processors are the same, the processing will be performed once).
- Greatly improved test coverage.

### Fixes

- Fix an issue when setting custom `loadKey` for the request, the `hashValue` of the default key was still used.
- Fix warnings "Decoding failed with error code -1" when progressively decoding images. This was the result of `ImageDecoder` trying to decode incomplete progressive scans.
- Fix an issue where `ImageDecoder` could produce a bit more progressive scans than necessary.


## Nuke 7.0.1

*May 16, 2018*

### Additions

- Add a section in README about replacing GIFs with video formats (e.g. `MP4`, `WebM`)
- Add proof of concept in the demo project that demonstrates loading, caching and displaying short `mp4` videos using Nuke

### Fixes

- #161 Fix the contentModes not set when initializing an ImageLoadingOptions object


## Nuke 7.0

*May 10, 2018*

Nuke 7 is the biggest release yet. It has a lot of  massive new features, new performance improvements, and some API refinements. Check out new [Nuke website](http://kean.blog/nuke) to see quick videos showcasing some of the new features.

Nuke 7 is almost completely source-compatible with Nuke 6.

### Progressive JPEG & WebP

Add support for progressive JPEG (built-in) and WebP (build by the [Ryo Kosuge](https://github.com/ryokosuge/Nuke-WebP-Plugin)). See [README](https://github.com/kean/Nuke) for more info. See demo project to see it in action.

Add new `ImageProcessing` protocol which now takes an extra `ImageProcessingContext` parameter. One of its properties is `scanNumber` which allows you to do things like apply blur to progressive image scans reducing blur radius with each new scan ("progressive blur").

### Resumable Downloads (HTTP Range Requests)

If the data task is terminated (either because of a failure or a cancellation) and the image was partially loaded, the next load will resume where it was left off. In many use cases resumable downloads are a massive improvement to user experience, especially on the mobile internet. 

Resumable downloads require the server support for [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators (`ETag` and `Last-Modified`).

The resumable downloads are enabled by default. The resumable data is automatically stored in efficient memory cache. This is a good default, but future versions might add more customization options.

### Loading Images into Views

Add a new set of powerful methods to load images into views. Here's one of those methods:

```swift
@discardableResult
public func loadImage(with request: ImageRequest,
                      options: ImageLoadingOptions = ImageLoadingOptions.shared,
                      into view: ImageDisplayingView,
                      progress: ImageTask.ProgressHandler? = nil,
                      completion: ImageTask.Completion? = nil) -> ImageTask?
```

You can now pass `progress` and `completion` closures as well as new  `ImageLoadingOptions` struct which offers a range of options:

```swift
public struct ImageLoadingOptions {
    public static var shared = ImageLoadingOptions()
    public var placeholder: Image?
    public var transition: Transition?
    public var failureImage: Image?
    public var failureImageTransition: Transition?
    public var isPrepareForReuseEnabled = true
    public var pipeline: ImagePipeline?
    public var contentModes: ContentModes?

    /// Content modes to be used for each image type (placeholder, success, failure).
    public struct ContentModes {
        public var success: UIViewContentMode
        public var failure: UIViewContentMode
        public var placeholder: UIViewContentMode
    }

    /// An animated image transition.
    public struct Transition {
        public static func fadeIn(duration: TimeInterval, options: UIViewAnimationOptions = [.allowUserInteraction]) -> Transition
        public static func custom(_ closure: @escaping (ImageDisplayingView, Image) -> Void) -> Transition
    }
}
```

`ImageView` will now also automatically prepare itself for reuse (can be disabled via `ImageLoadingOptions`)

Instead of an `ImageTarget` protocol we now have a new simple `ImageDisplaying` protocol which relaxes the requirement what can be used as an image view (it's `UIView & ImageDisplaying` now). This achieves two things:

- You can now add support for more classes (e.g. `MKAnnotationView` by implementing `ImageDisplaying` protocol
- You can override the `display(image:` method in `UIImageView` subclasses (e.g. `FLAnimatedImageView`)

### Image Pipeline

The previous  `Manager` + `Loading` architecture (terrible naming, responsibilities are often confusing) was replaced with a  new unified  `ImagePipeline` class. `ImagePipeline` was built from the ground-up to support all of the powerful new features in Nuke 7 (progressive decoding, resumable downloads, performance metrics, etc).

There is also a new `ImageTask` class which feels the gap where user or pipeline needed to communicate between each other after the request was started. `ImagePipeline` and `ImageTask` offer a bunch of new features:

- To cancel the request you now simply need to call `cancel()` on the task (`ImageTask`) which is a bit more user-friendly than previous `CancellationTokenSource` infrastructure.
- `ImageTask` offers a new way to track progress (in addition to closures) - native `Foundation.Progress` (created lazily)
- `ImageTask` can be used to dynamically change the priority of the executing tasks (e.g. the user opens a new screen, you lower the priority of outstanding tasks)
- In `ImagePipeline.Configuration` you can now provide custom queues (`OperationQueue`) for data loading, decoding and processing (separate queue for each stage).
- You can set a custom shared `ImagePipeline`.

### Animated Images (GIFs)

Add built-in support for animated images (everything expect the actual rendering). To enable rendering you're still going to need a third-party library (see [FLAnimatedImage](https://github.com/kean/Nuke-FLAnimatedImage-Plugin) and [Gifu](https://github.com/kean/Nuke-Gifu-Plugin) plugins). The changes made in Nuke dramatically simplified those plugins making both of them essentially obsolete - they both now have 10-30 lines of code, you can just copy this code into your project.

### Memory Cache Improvements

- Add new `ImageCaching` protocol for memory cache which now works with a new `ImageRespone` class. You can do much more intelligent things in your cache implementations now (e.g. make decisions on when to evict image based on HTTP headers).
- Improve cache write/hit/miss performance by 30% by getting rid of AnyHashable overhead. `ImageRequest` `cacheKey` and `loadKey` are now optional. If you use them, Nuke is going to use them instead of built-in internal `ImageRequest.CacheKey` and `ImageRequest.LoadKey`.
- Add `TTL` support in `ImageCache`

### Aggressive Disk Cache (Experimental)

Add a completely new custom LRU disk cache which can be used for fast and reliable *aggressive* data caching (ignores [HTTP cache control](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control)). The new cache lookups are up to 2x faster than `URLCache` lookups. You can enable it using pipeline's configuration:

When enabling disk cache you must provide a `keyEncoder` function which takes image request's url as a parameter and produces a key which can be used as a valid filename. The [demo project uses sha1](https://gist.github.com/kean/f5e1975e01d5e0c8024bc35556665d7b) to generate those keys.

```swift
$0.enableExperimentalAggressiveDiskCaching(keyEncoder: {
    guard let data = $0.cString(using: .utf8) else { return nil }
    return _nuke_sha1(data, UInt32(data.count))
})
```

The public API for disk cache and the API for using custom disk caches is going to be available in the future versions.

> Existing API already allows you to use custom disk cache by implementing `DataLoading` protocol, but this is not the most straightforward option.

### Performance Metrics

When optimizing performance, it's important to measure. Nuke collects detailed performance metrics during the execution of each image task:

```swift
ImagePipeline.shared.didFinishCollectingMetrics = { task, metrics in
    print(metrics)
}
```

![timeline](https://user-images.githubusercontent.com/1567433/39193766-8dfd81b2-47dc-11e8-86b3-f3f69dc73d3a.png)

```
(lldb) po metrics

Task Information {
    Task ID - 1
    Duration - 22:35:16.123 – 22:35:16.475 (0.352s)
    Was Cancelled - false
    Is Memory Cache Hit - false
    Was Subscribed To Existing Session - false
}
Session Information {
    Session ID - 1
    Total Duration - 0.351s
    Was Cancelled - false
}
Timeline {
    22:35:16.124 – 22:35:16.475 (0.351s) - Total
    ------------------------------------
    nil – nil (nil)                      - Check Disk Cache
    22:35:16.131 – 22:35:16.410 (0.278s) - Load Data
    22:35:16.410 – 22:35:16.468 (0.057s) - Decode
    22:35:16.469 – 22:35:16.474 (0.005s) - Process
}
Resumable Data {
    Was Resumed - nil
    Resumable Data Count - nil
    Server Confirmed Resume - nil
}
```

### Other Changes

- `ImagePreheater` now checks `ImageCache` synchronously before creating tasks which makes it slightly more efficient.
- `RateLimiter` now uses the same sync queue as the `ImagePipeline` reducing a number of dispatched blocks
- Smarter `RateLimiter` which no longer attempt to execute pending tasks when the bucket isn't full resulting in idle dispatching of blocks. I've used a CountedSet to see how well it works in practice and it's perfect. Nice small win.
- Add `ImageDecoderRegistry` to configure decoders globally.
- Add `ImageDecodingContext` to provide as much information as needed to select a decoder.
- `ImageTask.Completion` now contains `ImageResponse` (image + URLResponse) instead of just plain image.

### Deprecations

- `CancellationToken`, `CancellationTokenSource` - continued to be used internally, If you'd like to continue using cancellation tokens please consider copying this code into your project.
- `DataDecoding`, `DataDecoder`, `DataDecoderComposition` - replaced by a new image decoding infrastructure (`ImageDecoding`, `ImageDecoder`, `ImageDecodingRegistry` etc).
- `Request` renamed to `ImageRequest`.
- Deprecate `Result` type. It was only used in a single completion handler so it didn't really justify its existence. More importantly, I wasn't comfortable providing a public `Result` type as part of the framework.


# Nuke 6

## Nuke 6.1.1

*Apr 9, 2018*

- Lower macOS deployment target to 10.10. #156.
- Improve README: add detailed *Image Pipeline* section, *Performance* section, rewrite *Usage* guide


## Nuke 6.1

*Feb 24, 2018*

### Features

- Add `Request.Priority` with 5 available options ranging from `.veryLow` to `.veryHigh`. One of the use cases of `Request.Priority` is to lower the priority of preheating requests. In case requests get deduplicated the task's priority is set to the highest priority of registered requests and gets updated when requests are added or removed from the task.

### Improvements

- Fix warnings on Xcode 9.3 beta 3
- `Loader` implementation changed a bit, it is less clever now and is able to accommodate new features like request priorities
- Minor changes in style guide to make codebase more readable
- Switch to native `NSLock`, there doesn't seem to be any performance wins anymore when using `pthread_mutex` directly

### Fixes

- #146 fix disk cache path for macOS, thanks to @willdahlberg


## Nuke 6.0

*Dec 23, 2017*

> About 8 months ago I finally started using Nuke in production. The project has matured from a playground for experimenting with Swift features to something that I rely on in my day's job.

There are three main areas of improvements in Nuke 6:

- Performance. Nuke 6 is fast! The primary `loadImage(with:into:)` method is now **1.5x** faster thanks to performance improvements of [`CancellationToken`](https://kean.blog/post/cancellation-token), `Manager`, `Request` and `Cache` types. And it's not just main thread performance, many of the background operations were also optimized.
- API refinements. Some common operations that were surprisingly hard to do are not super easy. And there are no more implementation details leaking into a public API (e.g. classes like `Deduplicator`).
- Fixes some inconveniences like Thread Sanitizer warnings (false positives!). Improved compile time. Better documentation.

### Features

- Implements progress reporting https://github.com/kean/Nuke/issues/81
- Scaling images is now super easy with new convenience `Request` initialisers (`Request.init(url:targetSize:contentMode:` and `Request.init(urlRequest:targetSize:contentMode:`)
- Add a way to add anonymous image processors to the request (`Request.process(key:closure:)` and `Request.processed(key:closure:)`)
- Add `Loader.Options` which can be used to configure `Loader` (e.g. change maximum number of concurrent requests, disable deduplication or rate limiter, etc).

### Improvements

- Improve performance of [`CancellationTokenSource`](https://kean.blog/post/cancellation-token), `Loader`, `TaskQueue`
- Improve `Manager` performance by reusing contexts objects between requests
- Improve `Cache` by ~30% for most operations (hits, misses, writes)
- `Request` now stores all of the parameters in the underlying reference typed container (it used to store just reference typed ones). The `Request` struct now only has a single property with a reference to an underlying container.
- Parallelize image processing for up to 2x performance boost in certain scenarios. Might increase memory usage. The default maximum number of concurrent tasks is 2 and can be configured using `Loader.Options`.
- `Loader` now always call completion on the main thread.
- Move `URLResponse` validation from `DataDecoder` to `DataLoader`
- Make use of some Swift 4 feature like nested types inside generic types.
- Improve compile time.
- Wrap `Loader` processing and decoding tasks into `autoreleasepool` which reduced memory footprint.

### Fixes

- Get rid of Thread Sanitizer warnings in `CancellationTokenSource` (false positive)
- Replace `Foundation.OperationQueue` & custom `Foundation.Operation` subclass with a new `Queue` type. It's simpler, faster, and gets rid of pesky Thread Sanitizer warnings https://github.com/kean/Nuke/issues/141

### Removed APIs

- Remove global `loadImage(...)` functions https://github.com/kean/Nuke/issues/142
- Remove static `Request.loadKey(for:)` and `Request.cacheKey(for:)` functions. The keys are now simply returned in `Request`'s `loadKey` and `cacheKey` properties which are also no longer optional now.
- Remove `Deduplicator` class, make this functionality part of `Loader`. This has a number of benefits: reduced API surface, improves performance by reducing the number of queue switching, enables new features like progress reporting.
- Remove `Scheduler`, `AsyncScheduler`, `Loader.Schedulers`, `DispatchQueueScheduler`, `OperationQueueScheduler`. This whole infrastructure was way too excessive.
- Make `RateLimiter` private.
- `DataLoader` now works with `URLRequest`, not `Request`


# Nuke 5

## Nuke 5.2

*Sep 1, 2017*

Add support for both Swift 3.2 and 4.0.


## Nuke 5.1.1

*Jun 11, 2017*

- Fix Swift 4 warnings
- Add `DataDecoder.sharedUrlCache` to easy access for shared `URLCache` object
- Add references to [RxNuke](https://github.com/kean/RxNuke)
- Minor improvements under the hood


## Nuke 5.1

*Feb 23, 2017*

- De facto `Manager` has already implemented `Loading` protocol in Nuke 5 (you could use it to load images directly w/o targets). Now it also conforms to `Loading` protocols which gives access to some convenience functions available in `Loading` extensions.
- Add `static func targetSize(for view: UIView) -> CGSize` method to `Decompressor`
- Simpler, faster `Preheater`
- Improved documentation


## Nuke 5.0.1

*Feb 2, 2017*

- #116 `Manager` can now be used to load images w/o specifying a target
- `Preheater` is now initialized with `Manager` instead of object conforming to `Loading` protocol


## Nuke 5.0

*Feb 1, 2017*

### Overview

Nuke 5 is a relatively small release which removes some of the complexity from the framework.

One of the major changes is the removal of promisified API as well as `Promise` itself. Promises were briefly added in Nuke 4 as an effort to simplify async code. The major downsides of promises are compelex memory management, extra complexity for users unfamiliar with promises, complicated debugging, performance penalties. Ultimately I decided that promises were adding more problems that they were solving. 

### Changes

#### Removed promisified API and `Promise` itself

- Remove promisified API, use simple closures instead. For example, `Loading` protocol's method `func loadImage(with request: Request, token: CancellationToken?) -> Promise<Image>` was replaced with a method with a completion closure `func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)`. The same applies to `DataLoading` protocol.
- Remove `Promise` class
- Remove `PromiseResolution<T>` enum
- Remove `Response` typealias
- Add `Result<T>` enum which is now used as a replacement for `PromiseResolution<T>` (for instance, in `Target` protocol, etc)

#### Memory cache is now managed exclusively by `Manager`

- Remove memory cache from `Loader`
- `Manager` now not only reads, but also writes to `Cache`
- `Manager` now has new methods to load images w/o target (Nuke 5.0.1) 

The reason behind this change is to reduce confusion about `Cache` usage. In previous versions the user had to pass `Cache` instance to both `Loader` (which was both reading and writing to cache asynchronously), and to `Manager` (which was just reading from the cache synchronously). In a new setup it's clear who's responsible for managing memory cache.

#### Removed `DataCaching` and `CachingDataLoader`

Those two types were included in Nuke to make integrating third party caching libraries a bit easier. However, they were actually not that useful. Instead of using those types you could've just wrapped `DataLoader` yourself with a comparable amount of code and get much more control. For more info see [Third Party Libraries: Using Other Caching Libraries](https://github.com/kean/Nuke/blob/5.0/Documentation/Guides/Third%20Party%20Libraries.md). 

#### Other Changes

- `Loader` constructor now provides a default value for `DataDecoding` object
- `DataLoading` protocol now works with a `Nuke.Request` and not `URLRequest` in case some extra info from `URLRequest` is required
- Reduce default `URLCache` disk capacity from 200 MB to 150 MB
- Reduce default `maxConcurrentOperationCount` of `DataLoader` from 8 to 6
- Shared objects (like `Manager.shared`) are now constants.
- `Preheater` is now initialized with `Manager` instead of `Loading` object
- Add new [Third Party Libraries](https://github.com/kean/Nuke/blob/5.0/Documentation/Guides/Third%20Party%20Libraries.md) guide.
- Improved documentation


# Nuke 4

## Nuke 4.1.2

*Oct 22, 2016*

Bunch of improvements in built-in `Promise`:
- `Promise` now also uses new `Lock` - faster creation, faster locking
- Add convenience `isPending`, `resolution`, `value` and `error` properties
- Simpler implementation migrated from [Pill.Promise](https://github.com/kean/Pill)*

*`Nuke.Promise` is a simplified variant of [Pill.Promise](https://github.com/kean/Pill) (doesn't allow `throws`, adds `completion`, etc). The `Promise` is built into Nuke to avoid fetching external dependencies.


## Nuke 4.1.1

*Oct 4, 2016*

- Fix deadlock in `Cache` - small typo, much embarrassment  😄 (https://github.com/kean/Nuke-Alamofire-Plugin/issues/8)


## Nuke 4.1 ⚡️

*Oct 4, 2016*

Nuke 4.1 is all about **performance**. Here are some notable performance improvements:

- `loadImage(with:into:)` method with a default config is **6.3x** faster
- `Cache` operations (write/hit/miss) are from **3.1x** to **4.5x** faster

Nuke 4.0 focused on stability first, naturally there were some performance regressions. With the version 4.1 Nuke is again [the fastest framework](https://github.com/kean/Image-Frameworks-Benchmark) out there. The performance is ensured by a new set of performance tests.

<img src="https://cloud.githubusercontent.com/assets/1567433/19019388/26463bb2-888f-11e6-87dd-42c2d82c5dae.png" width="500"/>

If you're interested in the types of optimizations that were made check out recent commits. There is a lot of awesome stuff there!

Nuke 4.1 also includes a new [Performance Guide](https://github.com/kean/Nuke/blob/4.1/Documentation/Guides/Performance%20Guide.md) and a collection of [Tips and Tricks](https://github.com/kean/Nuke/blob/4.1/Documentation/Guides/Tips%20and%20Tricks.md).

### Other Changes

- Add convenience method `loadImage(with url: URL, into target: AnyObject, handler: @escaping Handler)` (more useful than anticipated).
- #88 Add convenience `cancelRequest(for:)` function
- Use `@discardableResult` in `Promise` where it makes sense
- Simplified `Loader` implementation
- `Cache` nodes are no longer deallocated recursively on `removeAll()` and `deinit` (I was hitting stack limit in benchmarks, it's impossible in real-world use).
- Fix: All `Cache` public `trim()` methods are now thread-safe too.


## Nuke 4.0 🚀

*Sep 19, 2016*

### Overview
 
Nuke 4 has fully adopted the new **Swift 3** changes and conventions, including the new [API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).
 
Nuke 3 was already a slim framework. Nuke 4 takes it a step further by simplifying almost all of its components.
 
Here's a few design principles adopted in Nuke 4:
 
- **Protocol-Oriented Programming.** Nuke 3 promised a lot of customization by providing a set of protocols for loading, caching, transforming images, etc. However, those protocols were vaguely defined and hard to implement in practice. Protocols in Nuke 4 are simple and precise, often consisting of a single method.
- **Single Responsibility Principle.** For example, instead of implementing preheating and deduplicating of equivalent requests in a single vague `ImageManager` class, those features were moved to separate classes (`Preheater`, `Deduplicator`). This makes core classes much easier to reason about.
- **Principle of Least Astonishment**. Nuke 3 had a several excessive protocols, classes and methods which are *all gone* now (`ImageTask`, `ImageManagerConfiguration` just to name a few). Those features are much easier to use now.
- **Simpler Async**. Image loading involves a lot of asynchronous code, managing it was a chore. Nuke 4 adopts two design patterns ([**Promise**](https://github.com/kean/Promise) and **CancellationToken**) that solve most of those problems.
 
The adoption of those design principles resulted in a simpler, more testable, and more concise code base (which is now under 900 slocs, compared to AlamofireImage's 1426, and Kingfisher's whopping 2357).
 
I hope that Nuke 4 is going to be a pleasure to use. Thanks for your interest 😄
 
You can learn more about Nuke 4 in an in-depth [**Nuke 4 Migration Guide**](https://github.com/kean/Nuke/blob/4.1/Documentation/Migrations/Nuke%204%20Migration%20Guide.md).

### Highlighted New Features
 
#### LRU Memory Cache
 
Nuke 4 features a new custom LRU memory cache which replaced `NSCache`. The primary reason behind this change was the fact that `NSCache` is not LRU]. The new `Nuke.Cache` has some other benefits like better performance, and more control which would enable some new advanced features in future versions.

#### Rate Limiter
 
There is a known problem with `URLSession` that it gets trashed pretty easily when you resume and cancel `URLSessionTasks` at a very high rate (say, scrolling a large collection view with images). Some frameworks combat this problem by simply never cancelling `URLSessionTasks` which are already in `.running` state. This is not an ideal solution, because it forces users to wait for cancelled requests for images which might never appear on the display.
 
Nuke has a better, classic solution for this problem - it introduces a new `RateLimiter` class which limits the rate at which `URLSessionTasks` are created. `RateLimiter` uses a [token bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm. The implementation supports quick bursts of requests which can be executed without any delays when "the bucket is full". This is important to prevent the rate limiter from affecting "normal" requests flow. `RateLimiter` is enabled by default.
 
You can see `RateLimiter` in action in a new `Rate Limiter Demo` added in the sample project.

#### Toucan Plugin

Make sure to check out new [Toucan plugin](https://github.com/kean/Nuke-Toucan-Plugin) which provides a simple API for processing images. It supports resizing, cropping, rounded rect masking and more.
 

# Nuke 3

## Nuke 3.2

*Sep 8, 2016*
 
 - Swift 2.3 support
 - Preheating is now thread-safe #75


## Nuke 3.1.3

*Jul 17, 2016*

#72 Fix synchronization issue in ImageManager loader:task:didFinishWithImage... method


## Nuke 3.1.2

*Jul 14, 2016*

- #71 ImageViewLoadingController now cancels tasks synchronously, thanks to @adomanico


## Nuke 3.1.1

*Jun 7, 2016*

- Demo project update to support CocoaPods 1.0
- #69 Bitcode support for Carthage builds, thanks to @vincentsaluzzo


## Nuke 3.1

*Apr 15, 2016*

- #64 Fix a performance regression: images are now decoded once per DataTask like they used to
- #65 Fix an issue custom on-disk cache (`ImageDiskCaching`) was called `setData(_:response:forTask:)` method when the error wasn't nil
- Add notifications for NSURLSessionTask state changes to enable activity indicators (based on https://github.com/kean/Nuke-Alamofire-Plugin/issues/4)


## Nuke 3.0

*Mar 26, 2016*

- Update for Swift 2.2
- Move `ImagePreheatController` to a standalone package [Preheat](https://github.com/kean/Preheat)
- Remove deprecated `suspend` method from `ImageTask`
- Remove `ImageFilterGaussianBlur` and Core Image helper functions which are now part of [Core Image Integration Guide](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide)
- Cleanup project structure (as expected by SPM)
- `Manager` constructor now has a default value for configuration
- `nk_setImageWith(URL:)` method no longer resizes images by default, because resizing is not effective in most cases
- Remove `nk_setImageWith(request:options:placeholder:)` method, it's trivial
- `ImageLoadingView` default implementation no longer implements "Cross Dissolve" animations, use `ImageViewLoadingOptions` instead (see `animations` or `handler` property)
- Remove `ImageViewDefaultAnimationDuration`, use `ImageViewLoadingOptions` instead (see `animations` property)
- `ImageDisplayingView` protocol now has a single `nk_displayImage(_)` method instead of a `nk_image` property
- Remove `nk_targetSize` property from `UI(NS)View` extension


# Nuke 2

## Nuke 2.3

*Mar 19, 2016*

- #60 Add custom on-disk caching support (see `ImageDiskCaching` protocol)
- Reduce dynamic dispatch


## Nuke 2.2

*Mar 11, 2016*

- `ImageTask` `suspend` method is deprecated, implementation does nothing
- `ImageLoader` now limits a number of concurrent `NSURLSessionTasks`
- Add `maxConcurrentSessionTaskCount` property to `ImageLoaderConfiguration`
- Add `taskReusingEnabled` property to `ImageLoaderConfiguration`
- Add [Swift Package Manager](https://swift.org/package-manager/) support
- Update documentation


## Nuke 2.1

*Feb 27, 2016*
 
- #57 `ImageDecompressor` now uses `CGImageAlphaInfo.NoneSkipLast` for opaque images 
- Add `ImageProcessorWithClosure` that can be used for creating anonymous image filters
- `ImageLoader` ensures thread safety of image initializers by running decoders on a `NSOperationQueue` with `maxConcurrentOperationCount=1`. However, `ImageDecoder` class is now also made thread safe.


## Nuke 2.0.1

*Feb 10, 2016*

- #53 ImageRequest no longer uses NSURLSessionTaskPriorityDefault, which requires CFNetwork that doesn't get added as a dependency automatically


## Nuke 2.0

*Feb 6, 2016*

Nuke now has an [official website](http://kean.blog/Nuke/)!

#### Main Changes

- #48 Update according to [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/). All APIs now just feel right.
- Add `UIImage` extension with helper functions for `Core Image`: `nk_filter(_:)`, etc.
- Add `ImageFilterGaussianBlur` as an example of a filter on top of `Core Image` framework
- Add `ImageRequestMemoryCachePolicy` enum that specifies the way `Manager` interacts with a memory cache; `NSURLRequestCachePolicy` no longer affects memory cache
- #17 Add `priority` to `ImageRequest`
- Add `removeResponseForKey()` method to `ImageMemoryCaching` protocol and the corresponding method to `Manager`
- Implement congestion control for `ImageLoader` that prevents `NSURLSession` trashing
- Simplify `ImageLoaderDelegate` by combining methods that were customizing processing in a single high-level method: `imageLoader(_:processorFor:image:)`. Users now have more control over processing
- Add `NSURLResponse?` parameter to `decode` method from `ImageDecoding` protocol
- `DataLoading` protocol no longer has `isLoadEquivalentRequest(_:toRequest)` and `isCacheEquivalentRequest(_:toRequest)`. Those methods are now part of `ImageLoaderDelegate` and they have default implementation
- `ImageResponseInfo` is now a struct
- Improved error reporting (codes are now stored in enum, more codes were added, error is now created with a failure reason)

#### UI Extensions Changes
- Move `nk_ImageTask(_:didFinishWithResponse:options)` method to `ImageLoadingView` protocol, that's really where it belongs to
- Add `handler` property to `ImageViewLoadingOptions` that allows you to completely override display/animate logic in `ImageLoadingView`
- Remove `nk_prepareForReuse` method from `ImageLoadingView` extensions (useless)
- Remove `placeholder` from `ImageViewLoadingOptions`, move it to a separate argument which is only available on `ImageDisplayingView`s
- Add `animated`, `userInfo` to `ImageViewLoadingOptions`
- `ImageViewLoadingOptions` is now nonull everywhere
- Add `setImageWith(task:options:)` method to `ImageViewLoadingController`

#### Other Changes

- If you add a completion handler for completed task, the response is now marked as `isFastResponse = true`
- Fix an issue that allowed incomplete image downloads to finish successfully when using built-in networking
- `equivalentProcessors(rhs:lhs:)` function is now private (and it also is renamed)
- Remove public `isLoadEquivalentToRequest(_:)` and `isCacheEquivalentToRequest(_:)` methods from `ImageRequest` extension
- Add `ImageTaskProgress` struct that represents load progress, move `fractionCompleted` property from `ImageTask` to `ImageTaskProgress`
- Remove public helper function `allowsCaching` from `ImageRequest` extension
- Remove deprecated `XCPSetExecutionShouldContinueIndefinitely` from playground


# Nuke 1

## Nuke 1.4

*Jan 9, 2016*

- #46 Add option to disable memory cache storage, thanks to @RuiAAPeres


## Nuke 1.3

*Dec 7, 2015*

- Add [Core Image Integration Guide](https://github.com/kean/Nuke/wiki/Core-Image-Integration-Guide)
- Fill most of the blanks in the documentation
- #47 Fix target size rounding errors in image downscaling (Pyry Jahkola @pyrtsa)
- Add `imageScale` property to `ImageDecoder` class that returns scale to be used when creating `UIImage` (iOS, tvOS, watchOS only)
- Wrap each iteration in `ProcessorComposition` in an `autoreleasepool`


## Nuke 1.2

*Nov 15, 2015*

- #20 Add preheating for UITableView (see ImagePreheatControllerForTableView class)
- #41 Enhanced tvOS support thanks to @joergbirkhold
- #39 UIImageView: ImageLoadingView extension no available on tvOS
- Add factory method for creating session tasks in DataLoader
- Improved documentation


## Nuke 1.1.1

*Oct 30, 2015*

- #35 ImageDecompressor now uses `32 bpp, 8 bpc, CGImageAlphaInfo.PremultipliedLast` pixel format which adds support for images in an obscure formats, including 16 bpc images.
- Improve docs


## Nuke 1.1

*Oct 23, 2015*

- #25 Add tvOS support
- #33 Add app extensions support for OSX target (other targets were already supported)


## Nuke 1.0

*Oct 18, 2015*

- #30 Add new protocols and extensions to make it easy to add full featured image loading capabilities to custom UI components. Here's how it works:
```swift
extension MKAnnotationView: ImageDisplayingView, ImageLoadingView {
    // That's it, you get default implementation of all the methods in ImageLoadingView protocol
    public var nk_image: UIImage? {
        get { return self.image }
        set { self.image = newValue }
    }
}
```
- #30 Add UIImageView extension instead of custom UIImageView subclass
- Back to the Mac! All new protocol and extensions for UI components (#30) are also available on a Mac, including new NSImageView extension.
- #26 Add `getImageTaskWithCompletion(_:)` method to Manager
- Add essential documentation
- Add handy extensions to ImageResponse


# Nuke 0.x

## Nuke 0.5.1

*Oct 13, 2015*

Nuke is now available almost [everywhere](https://github.com/kean/Nuke/wiki/Supported-Platforms). Also got rid of CocoaPods subspecs.

### New Supported Platforms

- CocoaPods, Nuke, watchOS
- CocoaPods, Nuke, OSX
- CocoaPods, NukeAlamofirePlugin, watchOS
- CocoaPods, NukeAlamofirePlugin, OSX
- Carthage, Nuke, watchOS
- Carthage, Nuke, OSX
- Carthage, NukeAlamofirePlugin, iOS
- Carthage, NukeAlamofirePlugin, watchOS
- Carthage, NukeAlamofirePlugin, OSX

### Repo Changes

- Remove Nuke/Alamofire subspec, move sources to separate repo [Nuke-Alamofire-Plugin](https://github.com/kean/Nuke-Alamofire-Plugin)
- Remove Nuke/GIF subspec, move sources to separate repo [Nuke-AnimatedImage-Plugin](https://github.com/kean/Nuke-AnimatedImage-Plugin)

### Code Changes

- #9, #19 ImageTask now has a closure for progress instead of NSProgress
- Rename ImageLoadingDelegate to ImageLoadingManager
- Add ImageLoaderDelegate with factory method to construct image decompressor, and `shouldProcessImage(_:)` method
- Make ImageRequest extensions public
- Make ImageTask constructor public; Annotate abstract methods.


## Nuke 0.5

*Oct 9, 2015*

This is a pre-1.0 version, first major release which is going to be available soon.

### Major

- #18 ImageTask can now be suspended (see `suspend()` method). Add `suspendLoadingForImageTask(_:)` method to `ImageLoading` protocol
- #24 ImageRequest can now be initialized with NSURLRequest. ImageDataLoading `imageDataTaskWithURL(_:progressHandler:completionHandler:)` method changed to `imageDataTaskWithRequest(_:progressHandler:completionHandler:)`. First parameter is ImageRequest, return value change from NSURLSessionDataTask to NSURLSessionTask.
- ImageLoader no longer limits number of concurrent NSURLSessionTasks (which had several drawbacks)
- Add base ImagePreheatingController class
- Multiple preheating improvements: significantly simplified implementation; visible index paths are now subtracted from preheat window; performance improvements.

### Minor

- BUGFIX: When subscribing to an existing NSURLSessionTask user was receiving progress callback with invalid totalUnitCount
- Add public `equivalentProcessors(lhs:rhs:) -> Bool` function that works on optional processors
- Add essential documentation


## Nuke 0.4

*Oct 4, 2015*

### Major

- Make ImageLoading protocol and ImageLoader class public
- Make ImageManager `cachedResponseForRequest(_:)` and `storeResponse(_:forRequest:)` methods public
- Make ImageRequestKey class and ImageRequestKeyOwner protocol public
- Remove unused ImageManaging and ImagePreheating protocols 

### Minor

- #13 BUGFIX: Crash on 32-bit iOS simulator on Mac with 16Gb+ of RAM (@RuiAAPeres)
- BUGFIX: Processing operation might not get cancelled in certain situations
- ImageProcessing protocol now provides default implementation for `isEquivalentToProcessor(_:)` method including separate implementation for processors that also conform to Equatable protocol.
- Add identifier: Int property to ImageTask
- ImageRequestKey now relies on Hashable and Equatable implementation provided by NSObject
- ImageMemoryCaching protocol now works with ImageRequestKey class

### Plumbing

- Adopt multiple Swift best practices (tons of them in fact)
- ImageManager is now fully responsible for memory caching and preheating, doesn't delegate any work to ImageLoader (simplifies its implementation and limits dependencies)
- Remove ImageRequestKeyType enum
- Rename ImageManagerLoader to ImageLoader
- Simply ImageManagerLoader (now ImageLoader) implementation
- Add multiple unit tests


## Nuke 0.3.1

*Sep 22, 2015*

#10 Fix Carthage build


## Nuke 0.3

*Sep 21, 2015*

- ImageTask now acts like a promise
- ImageManager.shared is now a property instead of a method
- ImageTask progress is now created lazily
- Add maxConcurrentTaskCount to ImageManagerConfiguration
- Move taskWithURL method to ImageManaging extension
- Add ImagePreheating protocol
- Multiple improvements across the board


## Nuke 0.2.2

*Sep 20, 2015*

- Add limited Carthage support (doesn't feature [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) and [Alamofire](https://github.com/Alamofire/Alamofire) integration yet, you'll have to stick with CocoaPods for that)
- ImageTask resume() and cancel() methods now return Self
- ImageTask completion property is now public
- Minor implementation improvements


## Nuke 0.2.1

*Sep 19, 2015*

- Add ImageCollectionViewPreheatingController (yep)
- Add [Image Preheating Guide](https://github.com/kean/Nuke/wiki/Image-Preheating-Guide)
- Add preheating demo


## Nuke 0.2

*Sep 18, 2015*

#### Major

- Optional [Alamofire](https://github.com/Alamofire/Alamofire) integration via 'Nuke/Alamofire' subspec
- Optional [FLAnimatedImage](https://github.com/Flipboard/FLAnimatedImage) integration via 'Nuke/GIF' subspec
- More concise API
- Add image filters to ImageRequest
- Add ImageManaging protocol
- Add ImageDecoderComposition
- Add ImageProcessorComposition
- watchOS
- Add convenience functions that forward calls to the shared manager

#### Minor

- Use ErrorType
- Add removeAllCachedImages method
- ImageRequest userInfo is now Any? so that you can pass anything including closures
- ImageResponseInfo now has userInfo: Any? property
- ImageResponseInfo is now a struct
- CachedImageResponse renamed to ImageCachedResponse; userInfo is now Any?
- Multiple improvements across the board


## Nuke 0

*Mar 11, 2015*

- Initial commit
