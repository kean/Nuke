# Nuke 7 Migration Guide

This guide is provided in order to ease the transition of existing applications using Nuke 6.x to the latest APIs, as well as explain the design and structure of new and changed functionality.

This migration guide is still work in progress, the finished version is going to be available when Nuke 7 is finally released.

## Requirements

- iOS 9.0, tvOS 9.0, macOS 10.11, watchOS 2.0
- Xcode 9.2
- Swift 4.0

## Overview

Nuke 7 is the biggest release yet. It contains more features and refinements that all of the previous releases combined. There are a lot of new APIs in Nuke 7, fortunately, it's almost completely source-compatible with Nuke 6. 

> Source-compatibility was removed in [Nuke 7.5](https://github.com/kean/Nuke/releases/tag/7.5). The latest source-compatible release is [Nuke 7.4.2](https://github.com/kean/Nuke/releases/tag/7.4.2). The best way to migrate would be to either upgrade to Nuke 7.4.2 first, or to drop this [Deprecated.swift](https://gist.github.com/kean/a14ca485ce72bef0e50cbb2f36ec7d91) into your project and follow the instructions from the warnings.

Most of the new APIs have `Image*` prefix. Some of the types with `Image*` prefix are new (e.g. `ImagePipeline` which replaced `Manager` and `Loader`), some were just renamed (e.g. `ImageRequest` instead of `Request`), and some are reimagining of old APIs (e.g. `ImageDecoding` instead of `Decoding`).

If you're using a deprecated API you're going to see a deprecation message with a suggestion which new API you should use instead. All of the deprecated APIs work exactly as they used to in the previous versions. The only exception is `DataLoading` protocol which was replaced with a new version, but most of the apps are not using it directly.
