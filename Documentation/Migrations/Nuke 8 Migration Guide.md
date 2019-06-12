# Nuke 8 Migration Guide

This guide is provided in order to ease the transition of existing applications using Nuke 7.x to the latest version, as well as explain the design and structure of new and changed functionality.

> To learn about the new features in Nuke 8 see the [release notes](https://github.com/kean/Nuke/releases/tag/8.0).

## Updated Minimum Requirements

- iOS 10.0, tvOS 10.0, macOS 10.12, watchOS 3.0
- Xcode 10.2
- Swift 5.0

## Overview

Nuke 8 contains a bunch of new features, refinements, and performance improvements. The default pipeline works exactly the same as in the previous version. The release is mostly source compatible with Nuke 7. The deprecated APIs were added to [Deprecated.swift](https://gist.github.com/kean/05eaa36ac72e4c34dea50911ee68b801) file where every declaration has a comment which guides you throught migration. There are still some breaking changes which might affect you which are covered in this guide.

> The deprecated APIs are going to be removed 6 months after the release. If by the time you upgrade to Nuke 8, the deprecated APIs are already removed, you can temporarily drop the [Deprecated.swift](https://gist.github.com/kean/05eaa36ac72e4c34dea50911ee68b801) into your project to ease the migration.

## `Result` Type

`ImageTask.Completion` closure now uses native `Result` type.

**Before:**

```swift
public typealias Completion = (Nuke.ImageResponse?, Nuke.ImagePipeline.Error?) -> Void
```

**After:**

```swift
public typealias Completion = (Result<Nuke.ImageResponse, Nuke.ImagePipeline.Error>) -> Void
```

You need to update all the place where you were using the completion closures.

```swift
// Before:
pipeline.loadImage(with: url) { response, error in
	if let response = response {
		// handle response
	} else {
		// handle error (optional)
	}
}

// After:
pipeline.loadImage(with: url) { result in
	switch result {
	case let .success(response):
		// handle response
	cae let .failure(error):
		// handle error (non optional)
	}
}
```

```swift
// Before:
pipeline.loadImage(with: url) { _, _ in }

// After:
pipeline.loadImage(with: url) { _ in }
```

## `ImageProcessing` Protocol

> **Affects you if you have any custom image processors.**

The `ImageProcessing` protocol was changed to support the new feature in Nuke 8 - [Caching Processed Images](https://github.com/kean/Nuke/pull/227). In order to generate cache keys, each processor now must return a unique string identifier. Instead of conforming to `Equatable` protocol, each processor now must also return a `hashableIdentifier` (`AnyHashable`) to be used by the memory cache for which string manipulations would be unacceptably slow.

**Before:**

```swift
public protocol ImageProcessing: Equatable {
    func process(image: Image, context: ImageProcessingContext) -> Image?
}
```

**After:**

```swift
public protocol ImageProcessing {
    func process(image: Image, context: ImageProcessingContext?) -> Image?
    var identifier: String { get }
    var hashableIdentifier: AnyHashable { get }
}
```

An example of migrating a custom processors.

**Before:**

```swift
struct GaussianBlur: ImageProcessing {
	let radius: Int

    func process(image: Image, context: ImageProcessingContext) -> Image? {
    	return /* create blurred image */
    }
}
```

**After:**

```swift
struct GaussianBlur: ImageProcessing, Hashable {
	let radius: Int

    func process(image: Image, context: ImageProcessingContext?) -> Image? {
    	return /* create blurred image */
    }

	// Prefer to use reverse DNS notation.
    var identifier: String { return "com.youdomain.processor.gaussianblur-\(radius)" }
    var hashableIdentifier: AnyHashable { return self }
}
```

## `AnyImageProcessor`

> **Affects you if you are explicitly using `AnyImageProcessor` struct.**

`AnyImageProcessor` was removed because it was no longer needed anymore. Anywhere where you used `AnyImageProcessor` before, you should now be able to pass the processor directly.


## `ImageDisplaying` Protocol

> **Affects you if you are using `ImageDisplaying` protocol directly.**

`ImageDisplaying` protocol was a pure @objc protocol which din't have any prefixes which meant that it could result in collisions with other methods/protocols in ObjC runtime. In order to reduce the change of collision, the `Nuke_` prefixes were added in Nuke 8.

**Before:**

```swift
@objc public protocol ImageDisplaying {
    @objc func display(image: Nuke.Image?)
}
```

**After:**

```swift
@objc public protocol Nuke_ImageDisplaying {
    @objc func nuke_display(image: Image?)
}
```

You need to update these protocols and method to the new methods.


