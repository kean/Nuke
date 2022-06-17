# ``Nuke``

Welcome to the documentation for Nuke, an image loading system for Apple platforms.

**Nuke ILS** provides a simple and efficient way to download and display images in your app. It's easy to learn and use thanks to a clear and concise API. Its advanced architecture enables many powerful features while offering virtually unlimited possibilities for customization.

Despite the number of features, the framework is lean and compiles in just under 3 seconds. Nuke has an automated test suite 2x the size of the codebase itself, ensuring excellent reliability. Every feature is carefully designed and optimized for performance.

## Overview

Nuke is easy to learn and use. The best way to learn is by using this website. Nuke provides three types of documentation: **guides**, **tutorials**, and an **API reference**.

The **guides** are available on this website and are split into three categories:

- **Basics** – user guides covering the basics of using the framework
- **Advanced** – user guides covering more advanced topics
- **Guides** – in-depth guides on specific topics

There is currently one up-to-date **tutorial** — [Nuke Tutorial for iOS: Getting Started](https://www.raywenderlich.com/11070743-nuke-tutorial-for-ios-getting-started) — written by the [raywenderlich.com](https://www.raywenderlich.com) team.

The **API reference** is hosted [separately](https://kean-org.github.io/docs/nuke/reference/10.2.0/) and is generated using [swift-doc](https://github.com/SwiftDocOrg/swift-doc).

## Getting Started

To learn Nuke, start with the basic guides and make your way through the documentation. Make sure to check out the [**demo project**](https://github.com/kean/NukeDemo). To install Nuke, use Swift Packager Manager.

> Upgrading from the previous version? Use a [**Migration Guide**](https://github.com/kean/Nuke/blob/10.0.0/Documentation/Migrations).

## Topics

### Essentials

- <doc:getting-started>
- <doc:image-requests>
- <doc:image-pipeline>
- ``ImageRequest``
- ``ImageRequestConvertible``
- ``ImageResponse``
- ``ImageContainer``

### Image Pipeline

<!--Articles-->
- <doc:image-pipeline-configuration>
- <doc:image-pipeline-guide>
- <doc:troubleshooting>

<!--Collections-->
- <doc:image-processing>
- <doc:loading-data>
- <doc:image-formats>

<!--Symbols-->
- ``ImagePipeline``
- ``ImagePipeline/Configuration-swift.struct``

// TODO: move image pipeline delegate to ImagePipeline somehow

- ``ImagePipelineDelegate``
- ``ImageTask``
- ``ImageTaskDelegate``
- ``ImageTaskEvent``

### Performance

<!--Articles-->
- <doc:performance-guide>
- <doc:prefetching>

<!--Collections-->
- <doc:caching>

<!--Symbols-->
- ``ImagePrefetcher``
