# Cache Configuration

Learn how to configure caching in Nuke.

## Overview

You have two built-in configurations ``ImagePipeline/Configuration-swift.struct`` to pick from:


Both configurations also have an LRU memory cache ``ImageCache`` enabled and ``ImageCache/shared`` across the pipelines. The size of the memory cache automatically adjusts based on the amount of memory on the device.

The default pipeline uses ``ImagePipeline/Configuration-swift.struct/withURLCache`` configuration by default. You can change the default pipeline by creating a new one:

```swift
ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
```

What configuration should use choose? It depends on your use case.

An **HTTP disk cache** (``ImagePipeline/Configuration-swift.struct/withURLCache`` option) gives the server precise control over caching via [`cache-control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) HTTP headers. You can specify what images to cache and for how long. The client can't also periodically check the cached response for [freshness](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching#freshness) and refresh if needed – useful for refreshing profile pictures or logos.

> Tip: Learn more about HTTP cache in ["Image Caching."](https://kean.blog/post/image-caching#http-caching)

An **aggressive LRU disk cache** (``ImagePipeline/Configuration-swift.struct/withDataCache`` option) ignores HTTP cache-control headers and _always_ stores fetched images, which works great for content that never changes. It can be much faster than `URLCache` in some situations and works great [offline](/nuke/guides/troubleshooting#cached-images-are-not-displaying-offline). Use this option in all situations except when you need HTTP cache control.
