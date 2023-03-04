# ``Nuke``

A powerful image loading system for Apple platforms.

## Overview

Nuke provides an efficient way to download and display images in your app. It's easy to learn and use. Its architecture enables many powerful features while offering virtually unlimited possibilities for customization.

The framework is lean and compiles in under 2 seconds. Nuke has an automated test suite 2x the size of the codebase itself, ensuring excellent reliability. Every feature is carefully designed and optimized for performance.

## Sponsors 💖

[Support](https://github.com/sponsors/kean) Nuke on GitHub Sponsors.

## Getting Started

Start learning with <doc:getting-started> and go through the rest of the articles in the documentation as you need it. Check out the [demo project](https://github.com/kean/NukeDemo) to see Nuke in action.

Upgrading from the previous version? Use a [Migration Guide](https://github.com/kean/Nuke/tree/master/Documentation/Migrations).

Looking for UI components? See [NukeUI](https://kean-docs.github.io/nukeui/documentation/nukeui/) and [NukeExtensions](https://kean-docs.github.io/nukeextensions/documentation/nukeextensions/) documentation.

To install Nuke, use Swift Packager Manager.

## Extensions

The image pipeline is easy to customize and extend. Check out the following first-class extensions and packages built by the community.

|Name|Description|
|--|--|
|[**Pulse**](https://github.com/kean/Pulse)|A network logging framework with easy [integration](https://github.com/kean/Nuke/pull/583)|
|[**Alamofire Plugin**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire)|
|[**NukeWebP**](https://github.com/makleso6/NukeWebP)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Maxim Kolesnik](https://github.com/makleso6)|
|[**WebP Plugin**](https://github.com/ryokosuge/Nuke-WebP-Plugin)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge)|
|[**AVIF Plugin**](https://github.com/delneg/Nuke-AVIF-Plugin)| **Community**. [AVIF](https://caniuse.com/avif) support, built by [Denis](https://github.com/delneg)|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples|

## Minimum Requirements

| Nuke | Date         | Swift | Xcode | Platforms                                     |
|------|--------------|-------|-------|-----------------------------------------------|
| 12.0 | Mar 4, 2023  | 5.6   | 13.3  | iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0 |
| 11.0 | Jul 20, 2022 | 5.6   | 13.3  | iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0 |
| 10.0 | June 1, 2021 | 5.3   | 12.0  | iOS 11.0, watchOS 4.0, macOS 10.13, tvOS 11.0 |
| 9.0  | May 20, 2020 | 5.1   | 11.0  | iOS 11.0, watchOS 4.0, macOS 10.13, tvOS 11.0 |
| 8.0  | July 8, 2019 | 5.0   | 10.2  | iOS 10.0, watchOS 3.0, macOS 10.12, tvOS 10.0 |
| 7.6  | Apr 7, 2019  | 4.2   | 10.1  | iOS 10.0, watchOS 3.0, macOS 10.12, tvOS 10.0 |
| 6.0  | Dec 23, 2017 | 4.0   | 9.2   | iOS 9.0, watchOS 2.0, macOS 10.11, tvOS 9.0   |
| 5.0  | Feb 1, 2017  | 3.0   | 8.0   | iOS 9.0, watchOS 2.0, macOS 10.11, tvOS 9.0   |
| 4.0  | Sep 19, 2016 | 3.0   | 8.0   | iOS 9.0, watchOS 2.0, macOS 10.11, tvOS 9.0   |
| 3.0  | Mar 26, 2016 | 2.2   | 7.3   | iOS 8.0, watchOS 2.0, macOS 10.9, tvOS 9.0    |
| 2.0  | Feb 6, 2016  | 2.0   | 7.1   | iOS 8.0, watchOS 2.0, macOS 10.9, tvOS 9.0    |
| 1.0  | Oct 18, 2015 | 2.0   | 7.0   | iOS 8.0, watchOS 2.0, macOS 10.9              |
| 0.2  | Sep 18, 2015 | 2.0   | 7.0   | iOS 8.0, watchOS 2.0                          |

## Topics

### Essentials

- <doc:getting-started>
- ``ImagePipeline``
- ``ImageRequest``
- ``ImageResponse``
- ``ImageTask``

### Customization

- <doc:image-processing>
- <doc:loading-data>
- <doc:image-formats>
- ``ImagePipelineDelegate``

### Performance

- <doc:performance-guide>
- <doc:prefetching>
- <doc:combine>
- <doc:caching>
- ``ImagePrefetcher``
