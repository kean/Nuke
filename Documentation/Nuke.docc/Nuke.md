# ``Nuke``

A powerful image loading system for Apple platforms.

## Overview

Nuke provides an efficient way to download and display images in your app. It's easy to learn and use. Its architecture enables many powerful features while offering virtually unlimited possibilities for customization.

The framework is lean and compiles in under 2 seconds. Nuke has an automated test suite 2x the codebase size, ensuring excellent reliability. Every feature is carefully designed and optimized for performance.

## Getting Started

Start learning with <doc:getting-started> and review the rest of the articles in the documentation as needed. Check out the [demo project](https://github.com/kean/NukeDemo) to see Nuke in action.

Upgrading from the previous version? Use a [Migration Guide](https://github.com/kean/Nuke/tree/master/Documentation/Migrations).

To install Nuke, use Swift Package Manager.

## Minimum Requirements

| Nuke | Date         | Swift | Xcode | Platforms                                                   |
|------|--------------|-------|-------|-------------------------------------------------------------|
| 13.0 | Mar 22, 2026 | 6.2   | 26.0  | iOS 15.0, watchOS 8.0, macOS 12.0, tvOS 13.0, visionOS 1.0  |
| 12.0 | Mar 4, 2023  | 5.7   | 14.1  | iOS 13.0, watchOS 6.0, macOS 10.15, tvOS 13.0               |

## Topics

### Essentials

- <doc:getting-started>
- <doc:swiftui>
- <doc:uikit>
- ``ImagePipeline``
- ``ImageRequest``
- ``ImageResponse``
- ``ImageTask``

### Customization

- <doc:image-processing>
- <doc:loading-data>
- <doc:image-formats>
- ``ImagePipeline/Delegate-swift.protocol``

### Performance

- <doc:performance-guide>
- <doc:prefetching>
- <doc:caching>
- ``ImagePrefetcher``
