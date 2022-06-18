# ``Nuke``

Welcome to the documentation for Nuke, an image loading system for Apple platforms.

## Overview

Nuke provides an efficient way to download and display images in your app. It's easy to learn and use. Its architecture enables many powerful features while offering virtually unlimited possibilities for customization.

The framework is lean and compiles in under 2 seconds¹. Nuke has an automated test suite 2x the size of the codebase itself, ensuring excellent reliability. Every feature is carefully designed and optimized for performance.

## Sponsors 💖

[Support](https://github.com/sponsors/kean) Nuke on GitHub Sponsors.

## Getting Started

The best way to start learning Nuke is by starting with <doc:getting-started> and going through the rest of the articles in the documentation. Make sure to check out the [demo project](https://github.com/kean/NukeDemo).

To install Nuke, use Swift Packager Manager.

> Tip: Upgrading from the previous version? Use a [Migration Guide](https://github.com/kean/Nuke/tree/master/Documentation/Migrations).

## Plugins

|Name|Description|
|--|--|
|[**Alamofire Plugin**](https://github.com/kean/Nuke-Alamofire-Plugin)|Replace networking layer with [Alamofire](https://github.com/Alamofire/Alamofire)|
|[**NukeWebP**](https://github.com/makleso6/NukeWebP)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Maxim Kolesnik](https://github.com/makleso6)|
|[**WebP Plugin**](https://github.com/ryokosuge/Nuke-WebP-Plugin)| **Community**. [WebP](https://developers.google.com/speed/webp/) support, built by [Ryo Kosuge](https://github.com/ryokosuge)|
|[**AVIF Plugin**](https://github.com/delneg/Nuke-AVIF-Plugin)| **Community**. [AVIF](https://caniuse.com/avif) support, built by [Denis](https://github.com/delneg)|
|[**Gifu Plugin**](https://github.com/kean/Nuke-Gifu-Plugin)|Use [Gifu](https://github.com/kaishin/Gifu) to load and display animated GIFs|
|[**RxNuke**](https://github.com/kean/RxNuke)|[RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke with examples|
|[**Xamarin NuGet**](https://github.com/roubachof/Xamarin.Forms.Nuke)| **Community**. Makes it possible to use Nuke from Xamarin|

## Minimum Requirements

| Nuke | Date         | Swift | Xcode | Platforms                                     |
|------|--------------|-------|-------|-----------------------------------------------|
| 11.0 | TBD          | 5.6   | 13.3  | iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0 |
| 10.0 | June 1, 2021 | 5.3   | 12.0  | iOS 11.0, watchOS 4.0, macOS 10.13, tvOS 11.0 |
| 9.0  | May 20, 2020 | 5.1   | 11.0  | iOS 11.0, watchOS 4.0, macOS 10.13, tvOS 11.0 |
| 8.0  | July 8, 2019 | 5.0   | 10.2  | iOS 10.0, watchOS 3.0, macOS 10.12, tvOS 10.0 |
| 7.6  | Apr 7, 2019  | 4.2   | 10.1  | iOS 10.0, watchOS 3.0, macOS 10.12, tvOS 10.0 |
| 6.0  | Dec 23, 2017 | 4.0   | 9.2   | iOS 9.0, watchOS 2.0, macOS 10.11, tvOS 9.0   |
| 5.0  | Feb 1, 2017  | 3.0   | 8.0   | iOS 9.0, watchOS 2.0, macOS 10.11, tvOS 9.0   |
| 4.0  | Sep 19, 2016 | 3.0   | 8.0   | iOS 9.0, watchOS 2.0, macOS 10.11, tvOS 9.0   |
| 3.0  | Mar 26, 2016 | 2.2   | 7.3   | iOS 8.0, watchOS 2.0, macOS 10.9, tvOS 9.0    |
| 2.0  | Feb 6, 2016  | 2.0   | 7.1   | iOS 8.0, watchOS 2.0, macOS 10.9, tvOS 9.0    |
| 2.0  | Feb 6, 2016  | 2.0   | 7.1   | iOS 8.0, watchOS 2.0, macOS 10.9, tvOS 9.0    |
| 1.0  | Oct 18, 2015 | 2.0   | 7.0   | iOS 8.0, watchOS 2.0, macOS 10.9              |
| 0.2  | Sep 18, 2015 | 2.0   | 7.0   | iOS 8.0, watchOS 2.0                          |

## Topics

### Essentials

- <doc:getting-started>
- <doc:image-pipeline>
- <doc:image-requests>
- ``ImagePipeline``
- ``ImageRequest``
- ``ImageResponse``
- ``ImageContainer``

### Customization

<!--Articles-->
- <doc:image-pipeline-configuration>

<!--Collections-->
- <doc:image-processing>
- <doc:loading-data>
- <doc:image-formats>

<!--Symbols-->
- ``ImagePipelineDelegate``
- ``ImageTask``
- ``ImageTaskDelegate``
- ``ImageRequestConvertible``

### Performance

<!--Articles-->
- <doc:performance-guide>
- <doc:prefetching>

<!--Collections-->
- <doc:caching>

<!--Symbols-->
- ``ImagePrefetcher``
