# Nuke 5 Migration Guide

This guide is provided in order to ease the transition of existing applications using Nuke 4.x to the latest APIs, as well as explain the design and structure of new and changed functionality.

## Requirements

- iOS 9.0, tvOS 9.0, macOS 10.11, watchOS 2.0
- Xcode 8
- Swift 3

## Overview

Nuke 5 is a relatively small release which removes some of the complexity from the framework. Chances are that changes made in Nuke 5 are not going to affect your code.

One of the major changes is the removal of promisified API as well as `Promise` itself. Promises were briefly added in Nuke 4 as an effort to simplify async code. But ultimately I decided that there were adding more problems that they were solving. The extra added complexity (especially in memory management, debugging) was too high, performance penalties of using Promises weren't welcome either. As a result I've decided to remove the Promises from Nuke altogether.

## Changes

### Remove promisified API and `Promise` itself

- Remove promisified API, use simple closures instead. For example, `Loading` protocol's method `func loadImage(with request: Request, token: CancellationToken?) -> Promise<Image>` was replaced with a method with a completion closure `func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)`. The same applies to `DataLoading` protocol.
- Remove `Promise` class
- Remove `PromiseResolution<T>` enum
- Remove `Response` typealias
- Add `Result<T>` enum which is now used as a replacement for `PromiseResolution<T>` (for instance, in `Target` protocol, etc)

If you've used promisified APIs you should replace them with a new closure-based APIs. If you still want to use promisified APIs please use [PromiseKit](https://github.com/mxcl/PromiseKit) (or other promise library) to wrap Nuke APIs.

Replace `PromiseResolution<T>` with `Result<T>` where necessary (custom `Target` conformances, custom `Manager.Handler`).

### Memory cache is now managed exclusively by `Manager`

- Remove memory cache from `Loader`
- `Manager` now not only reads, but also writes to `Cache`

If you are not using `Loader` directly this change doesn't affect you.

The reason behind this change is to reduce confusion about `Cache` usage. In previous versions the user had to pass `Cache` instance to both `Loader` (which was both reading and writing to cache asynchronously), and to `Manager` (which was just reading from the cache synchronously).

### Other Changes

- `Loader` constructor now provides a default value for `DataDecoding` object
- Default `URLCache` disk capacity reduced to 150 Mb
