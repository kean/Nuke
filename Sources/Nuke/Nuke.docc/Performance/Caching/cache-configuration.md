# Cache Configuration

Learn how to configure caching in Nuke.

## Overview

You have two built-in configurations ``ImagePipeline/Configuration-swift.struct`` to pick from:

- ``ImagePipeline/Configuration-swift.struct/withURLCache`` configuration with a ``DataLoader`` with an HTTP disk cache ([`URLCache`](https://developer.apple.com/documentation/foundation/urlcache)) with a size limit of 150 MB.

- ``ImagePipeline/Configuration-swift.struct/withDataCache`` configuration with an aggressive LRU disk cache ``DataCache`` with a size limit of 150 MB. An HTTP cache is disabled.

Both configurations also have an LRU memory cache ``ImageCache`` enabled and ``ImageCache/shared`` across the pipelines. The size of the memory cache automatically adjusts based on the amount of memory on the device.

The default pipeline uses ``ImagePipeline/Configuration-swift.struct/withURLCache`` configuration by default. You can change the default pipeline by creating a new one:

```swift
ImagePipeline.shared = ImagePipeline(configuration: .withDataCache)
```

What configuration should use choose? It depends on your use case.

An **HTTP disk cache** (``ImagePipeline/Configuration-swift.struct/withURLCache`` option) gives the server precise control over caching via [`cache-control`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control) HTTP headers. You can specify what images to cache and for how long. The client can't also periodically check the cached response for [freshness](https://developer.mozilla.org/en-US/docs/Web/HTTP/Caching#freshness) and refresh if needed – useful for refreshing profile pictures or logos.

> Tip: Learn more about HTTP cache in ["Image Caching."](https://kean.blog/post/image-caching#http-caching)

An **aggressive LRU disk cache** (``ImagePipeline/Configuration-swift.struct/withDataCache`` option) ignores HTTP cache-control headers and _always_ stores fetched images, which works great for content that never changes. It can be much faster than `URLCache` in some situations and works great [offline](/nuke/guides/troubleshooting#cached-images-are-not-displaying-offline). Use this option in all situations except when you need HTTP cache control.

## Cache Policy

If you use an aggressive disk cache ``DataCache``, which is a recommended option, you can specify a cache policy ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum``. There are four available options:

| Policy          | Description           |
|---------------|-----------------|
|``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/automatic``|For requests with processors, encode and store processed images. For requests with no processors, store original image data, unless the resource is local (file:// or data:// scheme is used).|
|``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeOriginalData``|For all requests, only store the original image data, unless the resource is local (file:// or data:// scheme is used)|
|``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeEncodedImages``|For all requests, encode and store decoded images after all processors are applied. This is useful if you want to store images in a format different than provided by a server, e.g. decompressed. In other scenarios, consider using .automatic policy instead.|
|``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeAll``|For requests with processors, encode and store processed images. For all requests, store original image data|

The default policy is ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeOriginalData``.

> Important: With ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/automatic`` and ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeEncodedImages`` policies, the pipeline ``ImagePipeline/loadData(with:queue:progress:completion:)`` method will not store the images in the disk cache for requests with any processors applied – this method only loads data and doesn't decode images. This also affects how ``ImagePrefetcher`` with a ``ImagePrefetcher/Destination/diskCache`` destination works.
