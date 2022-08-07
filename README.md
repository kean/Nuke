<br/>

<img src="https://user-images.githubusercontent.com/1567433/114792417-57c1d080-9d56-11eb-8035-dc07cfd7557f.png" height="205">

# Image Loading System

<p align="left">
<img src="https://img.shields.io/badge/platforms-iOS%2C%20macOS%2C%20watchOS%2C%20tvOS-lightgrey.svg">
<img src="https://github.com/kean/Nuke/workflows/Nuke%20CI/badge.svg">
</p>

Nuke provides an efficient way to download and display images in your app. It's easy to learn and use. Its architecture enables many powerful features while offering virtually unlimited possibilities for customization.

The framework is lean and compiles in under 2 seconds[¹](#footnote-1). Nuke has an automated test suite 2x the size of the codebase itself, ensuring excellent reliability. Every feature is carefully designed and optimized for [performance](https://kean.blog/post/nuke-9).

> **Fast LRU memory and disk cache** · **SwiftUI** · **Smart background decompression** · **Image processing** · **Resumable downloads** · **Intelligent deduplication** · **Request prioritization** · **Prefetching** · **Rate limiting** · **Progressive JPEG, HEIF, WebP, SVG, GIF** · **Alamofire** · **Combine** · **Async/Await**

## Sponsors

<a target="_blank" rel="noopener noreferrer" href="https://getstream.io/chat/sdk/swiftui/?utm_source=Nuke&utm_medium=Github_Repo_Content_Ad&utm_content=Developer&utm_campaign=Nuke_July2022_SwiftUIChat_klmh22#gh-light-mode-only"><img src="https://user-images.githubusercontent.com/1567433/175186173-64eb53cb-b5d6-4ed4-aaca-87dbbb0834ab.png#gh-light-mode-only" width="300px" alt="Stream Logo" style="max-width: 100%;"></a>
<a target="_blank" rel="noopener noreferrer" href="https://getstream.io/chat/sdk/swiftui/?utm_source=Nuke&utm_medium=Github_Repo_Content_Ad&utm_content=Developer&utm_campaign=Nuke_July2022_SwiftUIChat_klmh22#gh-dark-mode-only"><img src="https://user-images.githubusercontent.com/1567433/175562043-0ab82adc-e3c7-4c0b-8813-a7940ff41db8.png#gh-dark-mode-only" width="244px" alt="Stream Logo" style="max-width: 100%;"></a>

Nuke is proudly sponsored by [Stream](https://getstream.io/chat/sdk/swiftui/?utm_source=Nuke&utm_medium=Github_Repo_Content_Ad&utm_content=Developer&utm_campaign=Nuke_July2022_SwiftUIChat_klmh22), the leading provider in enterprise grade Feed & Chat APIs.

> [Support](https://github.com/sponsors/kean) Nuke on GitHub Sponsors.

## Documentation

Nuke is easy to learn and use thanks to documentation generated using DocC: [**Nuke**](https://kean-docs.github.io/nuke/documentation/nuke/getting-started/), [**NukeUI**](https://kean-docs.github.io/nukeui/documentation/nukeui/), [**NukeExtensions**](https://kean-docs.github.io/nukeextensions/documentation/nukeextensions/). Make sure to also check out [**Nuke Demo**](https://github.com/kean/NukeDemo).

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/tree/master/Documentation/Migrations).

<a href="https://kean-docs.github.io/nuke/documentation/nuke/getting-started">
<img width="690" alt="Nuke Docs" src="https://user-images.githubusercontent.com/1567433/175793167-b7e0c557-b887-444f-b18a-57d6f5ecf01a.png">
</a>

## Integrations

Nuke provides an easy way to integrate [Pulse](https://github.com/kean/Pulse), a network logging framework  optimized for images.

## Extensions

The image pipeline is easy to customize and extend. Check out the following first-class extensions and packages built by the community.

|Name|Description|
|--|--|
|[**Alamofire Plugin**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire)|
|[**NukeWebP**](https://github.com/makleso6/NukeWebP)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Maxim Kolesnik](https://github.com/makleso6)|
|[**WebP Plugin**](https://github.com/ryokosuge/Nuke-WebP-Plugin)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge)|
|[**AVIF Plugin**](https://github.com/delneg/Nuke-AVIF-Plugin)| **Community**. [AVIF](https://caniuse.com/avif) support, built by [Denis](https://github.com/delneg)|
|[**Gifu Plugin**](https://github.com/kean/Nuke-Gifu-Plugin)|Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples|

## Minimum Requirements

| Nuke       | Date         | Swift       | Xcode      | Platforms                                     |
|------------|--------------|-------------|------------|-----------------------------------------------|
| Nuke 11.0  | Jul 20, 2022 | Swift 5.6   | Xcode 13.3 | iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0 |
| Nuke 10.0  | Jun 1, 2021  | Swift 5.3   | Xcode 12.0 | iOS 11.0, watchOS 4.0, macOS 10.13, tvOS 11.0 |

## License

Nuke is available under the MIT license. See the LICENSE file for more info.

----

> <a name="footnote-1">¹</a> Measured on MacBook Pro 14" 2021 (10-core M1 Pro)
