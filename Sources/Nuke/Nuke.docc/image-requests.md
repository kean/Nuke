# Image Requests

``ImageRequest`` allows you to set image processors, change the request priority, and more.

## Overview

``ImageRequest`` allows you to set image processors, change the request priority, and more.

```swift
let request = ImageRequest(
    url: URL(string: "http://example.com/image.jpeg"),
    processors: [ImageProcessors.Resize(size: imageView.bounds.size)],
    priority: .high,
    options: [.reloadIgnoringCacheData]
)
Nuke.loadImage(with: url, into: imageView)
```

## Processors

Set ``ImageRequest/processors`` to apply one of the built-in processors that can be found in ``ImageProcessors`` namespace or a custom one.

```swift
var request = ImageRequest(url: URL(string: "http://..."))
request.processors = [ImageProcessors.Resize(size: imageView.bounds.size)]
```

> Tip: Another way to apply processors is by setting the default ``ImagePipeline/Configuration-swift.struct/processors`` on ``ImagePipeline/Configuration-swift.struct``.

> Tip: See <doc:image-processing> for more information on image processing.

## Priority

The execution priority of the request. The priority affects the order in which the image requests are executed. By default, `.normal`.

> The priority management is key for Nuke performance. ``ImagePrefetcher`` uses `.low` priority to avoid interfering with `.normal` requests.

> Tip: You can change the priority of a running task using ``ImageTask/priority``.

```swift
var request = ImageRequest(url: URL(string: "http://..."))
request.priority = .high
```

## Options

By default, the pipeline makes full use of all of its caching layers. You can change this behavior using ``ImageRequest/Options-swift.struct``. For example, you can ignore local caches using ``ImageRequest/Options-swift.struct/reloadIgnoringCachedData`` option.

```swift
var request = ImageRequest(url: URL(string: "http://..."))
request.options = [.reloadIgnoringCachedData]
```

Another useful cache policy is ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad`` that allows you to existing cache data and fail if no cached data is available.

> Tip: See <doc:caching> for more information on caching.

## User Info

You can also provide custom options to the request via ``ImageRequest/userInfo``. There are also some rarely used built-in options that are passed via ``ImageRequest/userInfo`.

By default, a pipeline uses URLs as unique image identifiers for caching and task coalescing. You can override this behavior by providing an ``ImageRequest/UserInfoKey/imageIdKey`` instead. For example, you can use it to remove transient query parameters from the request.

```swift
let request = ImageRequest(
    url: URL(string: "http://example.com/image.jpeg?token=123"),
    userInfo: [.imageIdKey: "http://example.com/image.jpeg"]
)
```

## Sources

The request can be instantiated either with a [`URL`](https://developer.apple.com/documentation/foundation/url) or with a [`URLRequest`](https://developer.apple.com/documentation/foundation/urlrequest).

```swift
let urlRequest = URLRequest(url: imageUrl, cachePolicy: .returnCacheDataDontLoad)
let request = ImageRequest(urlRequest: urlRequest)
```

If you have a custom data source or want to process image data from memory, you can also use a special Combine-based initializer.

```swift
let request = ImageRequest(
    id: "image-01",
    data: Just(data),
    processors: [ImageProcessors.Resize(width: 44)]
)
```
