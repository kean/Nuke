# Nuke 5 Migration Guide

This guide is provided in order to ease the transition of existing applications using Nuke 4.x to the latest APIs, as well as explain the design and structure of new and changed functionality.

## Requirements

- iOS 9.0, tvOS 9.0, macOS 10.11, watchOS 2.0
- Xcode 8
- Swift 3

## Overview

Nuke 5 is a relatively small release which removes some of the complexity from the framework. Hopefully it will make *contributing* to Nuke easier.

One of the major changes is the removal of promisified API as well as `Promise` itself. Promises were briefly added in Nuke 4 as an effort to simplify async code. The major downsides of promises are compelex memory management, extra complexity for users unfamiliar with promises, complicated debugging, performance penalties. Ultimately I decided that promises were adding more problems that they were solving. 

Chances are that changes made in Nuke 5 are not going to affect your code.

## Changes

### Removed promisified API and `Promise` itself

> - Remove promisified API, use simple closures instead. For example, `Loading` protocol's method `func loadImage(with request: Request, token: CancellationToken?) -> Promise<Image>` was replaced with a method with a completion closure `func loadImage(with request: Request, token: CancellationToken?, completion: @escaping (Result<Image>) -> Void)`. The same applies to `DataLoading` protocol.
> - Remove `Promise` class
> - Remove `PromiseResolution<T>` enum
> - Remove `Response` typealias
> - Add `Result<T>` enum which is now used as a replacement for `PromiseResolution<T>` (for instance, in `Target` protocol, etc)

- If you've used promisified APIs you should replace them with a new closure-based APIs. If you still want to use promisified APIs please use [PromiseKit](https://github.com/mxcl/PromiseKit) or some other promise library to wrap Nuke APIs.
- If you've provided a custom `Loading` or `DataLoading` protocols you should update them to a new closure-based APIs.
- Replace `PromiseResolution<T>` with `Result<T>` where necessary (custom `Target` conformances, custom `Manager.Handler`).

### Memory cache is now managed exclusively by `Manager`

> - Remove memory cache from `Loader`
> - `Manager` now not only reads, but also writes to `Cache`
> - `Manager` now has new methods to load images w/o target (Nuke 5.0.1)

- If you're not constructing a custom `Loader` and you're not using it directly this change doesn't affect you
- If you're using custom `Loader` directly and rely on its memory caching please new `Manager` APIs that load images w/o target
- If you're constructing a custom `Loader` but don't use it directly then simply update to a new initializer which not longer requires you to pass memory cache in

### Removed `DataCaching` and `CachingDataLoader`

- Instead of using those types you'll need to wrap `DataLoader` by yourself. For more info see [Third Party Libraries: Using Other Caching Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries). 

### Other Changes

Make sure that you take those minor changes into account to:

> - `Loader` constructor now provides a default value for `DataDecoding` object
> - `DataLoading` protocol now works with a `Nuke.Request` and not `URLRequest` in case some extra info from `URLRequest` is required
> - Reduce default `URLCache` disk capacity from 200 MB to 150 MB
> - Reduce default `maxConcurrentOperationCount` of `DataLoader` from 8 to 6.
> - Shared objects (like `Manager.shared`) are now constants.
> - `Preheater` is now initialized with `Manager` instead of `Loading` object
