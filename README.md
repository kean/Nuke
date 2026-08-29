<br/>
<img src="https://user-images.githubusercontent.com/1567433/114792417-57c1d080-9d56-11eb-8035-dc07cfd7557f.png" height="170px">

# Image Loading System

<p align="left">
<img src="https://img.shields.io/badge/platforms-iOS%2C%20macOS%2C%20watchOS%2C%20tvOS%2C%20visionOS-lightgrey.svg">
<img src="https://img.shields.io/badge/Licence-MIT-green">
</p>

> *Serving Images Since 2015*

Load images from different sources and display them in your app using simple and flexible APIs. Take advantage of the powerful image processing capabilities and a robust caching system.

The framework is lean – 31 public types in the core module – and has an automated test suite 2x the codebase size, ensuring excellent reliability. Nuke is optimized for [performance](https://kean-docs.github.io/nuke/documentation/nuke/performance-guide), and its advanced architecture enables virtually unlimited possibilities for customization.

> **Typed Errors** · **Memory and Disk Cache** · **Image Processing & Decompression** · **Request Coalescing & Priority** · **Prefetching** · **Resumable Downloads** · **Progressive JPEG** · **HEIF, WebP, GIF** · **SwiftUI** · **Async/Await**

## Sponsors

<table>
  <tr>
    <td valign="center" align="center">
        <a href="https://proxyman.io">
          <img src="https://kean.blog/images/logos/proxyman.png" height="50px" alt="Proxyman Logo">
          <p>Proxyman</p>
        </a>
    </td>
  </tr>
</table>

## Usage

Load images using `ImagePipeline` from the lean core [**Nuke**](https://kean-docs.github.io/nuke/documentation/nuke) module:

```swift
func loadImage() async throws {
    let imageTask = ImagePipeline.shared.imageTask(with: url)
    for await progress in imageTask.progress {
        // Update progress
    }
    imageView.image = try await imageTask.image
}
```

Or use the built-in UI components from [**NukeUI**](https://kean-docs.github.io/nukeui/documentation/nukeui/). `LazyImage(url:)` covers the common case, and the `state` closure hands you the typed `ImagePipeline.Error` the pipeline threw:

```swift
LazyImage(url: url) { state in
    if case .dataDownloadExceededMaximumSize = state.error {
        Text("Image too large")   // no cast, no `as?`
    } else if let image = state.image {
        image.resizable()
    }
}
```

The [**Getting Started**](https://kean-docs.github.io/nuke/documentation/nuke/getting-started/) guide is the best place to start. Check out [**Nuke Demo**](https://github.com/kean/NukeDemo) for more examples.

<a href="https://kean-docs.github.io/nuke/documentation/nuke/getting-started">
<img width="747" alt="Nuke Docs and Demo" src="https://github.com/user-attachments/assets/c6bbac09-55f2-4824-a0ec-a3a467d9e9be" />
</a>

## Installation

Nuke supports [Swift Package Manager](https://www.swift.org/package-manager/), which is the recommended option. If that doesn't work for you, you can use binary frameworks attached to the [releases](https://github.com/kean/Nuke/releases).

The package ships with four modules that you can install depending on your needs:

|Module|Description|
|--|--|
|[**Nuke**](https://kean-docs.github.io/nuke/documentation/nuke)|The lean core framework with `ImagePipeline`, `ImageRequest`, and more|
|[**NukeUI**](https://kean-docs.github.io/nukeui/documentation/nukeui/)|The UI components: `LazyImage` (SwiftUI), `LazyImageView` and `UIImageView` extensions (UIKit, AppKit)|
|[**NukeVideo**](https://kean-docs.github.io/nukevideo/documentation/nukevideo/)|The components for decoding and playing short videos|
|**NukeExtensions**|**Deprecated**. An empty shim that re-exports `NukeUI`, where the image view extensions moved in Nuke 14. Scheduled for removal in Nuke 15|

## Extensions

The image pipeline is easy to customize and extend. Check out the following first-class extensions and packages built by the community.

|Name|Description|
|--|--|
|[**Alamofire Plugin**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire)|
|[**NukeWebP**](https://github.com/makleso6/NukeWebP)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Maxim Kolesnik](https://github.com/makleso6)|
|[**WebP Plugin**](https://github.com/ryokosuge/Nuke-WebP-Plugin)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge)|
|[**AVIF Plugin**](https://github.com/delneg/Nuke-AVIF-Plugin)| **Community**. [AVIF](https://caniuse.com/avif) support, built by [Denis](https://github.com/delneg)|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples|

> Looking for a way to log your network requests, including image requests? Check out [**Pulse**](https://github.com/kean/Pulse).

## What's New in Nuke 14

- **Typed errors, end to end.** `ImagePipeline` and `ImageTask` are declared `throws(ImagePipeline.Error)`, and `NukeUI` surfaces the same type instead of erasing it: `LazyImageState.error`, `FetchImage.result`, and `onCompletion` all carry it, so branching on a case needs no cast.
- **`NukeExtensions` folded into `NukeUI`.** `loadImage(with:into:)` and friends now live alongside the other UIKit and AppKit views. `NukeExtensions` remains as a shim that re-exports `NukeUI` and is removed in Nuke 15.
- **Combine APIs removed.** `ImagePipeline.imagePublisher(with:)` and the publisher-based `FetchImage.load(_:)` are gone – use the Async/Await APIs.

The [**Nuke 14 Migration Guide**](https://github.com/kean/Nuke/blob/main/Documentation/Migrations/Nuke%2014%20Migration%20Guide.md) covers these and the rest of the changes.

## Minimum Requirements

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/tree/main/Documentation/Migrations).

> **Nuke 14 is in development** on `main` and its requirements aren't final. The latest release is [Nuke 13](https://github.com/kean/Nuke/releases/latest).

| Nuke            | Swift     | Xcode      | Platforms                                                   |
|-----------------|-----------|------------|-------------------------------------------------------------|
| Nuke 14.0 (WIP) | Swift 6.2 | Xcode 26.0 | iOS 16.0, watchOS 9.0, macOS 13.0, tvOS 16.0, visionOS 1.0  |
| Nuke 13.0       | Swift 6.2 | Xcode 26.0 | iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 15.0, visionOS 1.0  |
| Nuke 12.0       | Swift 5.7 | Xcode 15.0 | iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0               |

## License

Nuke is available under the MIT license. See the LICENSE file for more info.
