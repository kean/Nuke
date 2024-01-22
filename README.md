<br/>
<img src="https://user-images.githubusercontent.com/1567433/114792417-57c1d080-9d56-11eb-8035-dc07cfd7557f.png" height="170px">

# Image Loading System

<p align="left">
<img src="https://img.shields.io/badge/platforms-iOS%2C%20macOS%2C%20watchOS%2C%20tvOS%2C%20visionOS-lightgrey.svg">
</p>

Load images from different sources and display them in your app using simple and flexible APIs. Take advantage of the powerful image processing capabilities and a robust caching system.

The framework is lean and compiles in under 2 seconds[¹](#footnote-1). It has an automated test suite 2x the codebase size, ensuring excellent reliability. Nuke is optimized for [performance](https://kean-docs.github.io/nuke/documentation/nuke/performance-guide), and its advanced architecture enables virtually unlimited possibilities for customization.

> **Fast LRU memory and disk cache** · **SwiftUI** · **Smart background decompression** · **Image processing** · **Resumable downloads** · **Intelligent deduplication** · **Request prioritization** · **Prefetching** · **Rate limiting** · **Progressive JPEG, HEIF, WebP, SVG, GIF** · **Alamofire** · **Combine** · **Async/Await**

## Sponsors

<table>
  <tr>
    <td valign="center">
        <a href="https://proxyman.io"><img src="https://kean.blog/images/logos/proxyman.png" height="40px" alt="Proxyman Logo"></a>
    </td>
    <td valign="center">
        <a href="https://www.namiml.com#gh-light-mode-only"><img src="https://kean.blog/images/logos/nami-light.png#gh-light-mode-only" height="40px" alt="Nami Logo"></a><a href="https://www.namiml.com#gh-dark-mode-only"><img src="https://kean.blog/images/logos/nami-dark.png#gh-dark-mode-only" height="40px" alt="Nami Logo"></a>
    </td>
  </tr>
</table>

> [Support](https://github.com/sponsors/kean) Nuke on GitHub Sponsors.

## Installation

Nuke supports [Swift Package Manager](https://www.swift.org/package-manager/), which is the recommended option. If that doesn't work for you, you can use binary frameworks attached to the [releases](https://github.com/kean/Nuke/releases).

## Documentation

Nuke is easy to learn and use thanks to documentation generated using DocC: [**Nuke**](https://kean-docs.github.io/nuke/documentation/nuke/getting-started/), [**NukeUI**](https://kean-docs.github.io/nukeui/documentation/nukeui/), [**NukeExtensions**](https://kean-docs.github.io/nukeextensions/documentation/nukeextensions/). Make sure to also check out [**Nuke Demo**](https://github.com/kean/NukeDemo).

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/tree/master/Documentation/Migrations).

<a href="https://kean-docs.github.io/nuke/documentation/nuke/getting-started">
<img width="690" alt="Nuke Docs" src="https://user-images.githubusercontent.com/1567433/175793167-b7e0c557-b887-444f-b18a-57d6f5ecf01a.png">
</a>

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

## Minimum Requirements

| Nuke       | Date         | Swift       | Xcode      | Platforms                                     |
|------------|--------------|-------------|------------|-----------------------------------------------|
| Nuke 12.0  | Mar 4, 2023  | Swift 5.7   | Xcode 14.1 | iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0 |
| Nuke 11.0  | Jul 20, 2022 | Swift 5.6   | Xcode 13.3 | iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0 |
| Nuke 10.0  | Jun 1, 2021  | Swift 5.3   | Xcode 12.0 | iOS 11.0, watchOS 4.0, macOS 10.13, tvOS 11.0 |

> Starting with version 12.3, Nuke also ships with visionOS support (in beta)

## License

Nuke is available under the MIT license. See the LICENSE file for more info.

----

> <a name="footnote-1">¹</a> Measured on MacBook Pro 14" 2021 (10-core M1 Pro)
