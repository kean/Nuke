# Nuke 6 Migration Guide

This guide is provided in order to ease the transition of existing applications using Nuke 5.x to the latest APIs, as well as explain the design and structure of new and changed functionality.

## Requirements

- iOS 9.0, tvOS 9.0, macOS 10.11, watchOS 2.0
- Xcode 9
- Swift 4

## Overview

Nuke 6 has a relatively small number of changes in the public API, chances are most of them are not going to affect your projects. Most of the deprecated APIs are kept in the project to ease the transition, however, they are going to be removed fairly soon.

There were a lot of implementation details leaking into the public API in Nuke 5 (e.g. `Deduplicator` class, scheduling infrastracture) which were all made private in Nuke 6. If you were using any of those APIs you can always ping me with your questions on [Twitter](https://twitter.com/a_grebenyuk).
