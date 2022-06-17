# Image Requests

Learn how to create and customize image requests.

## Overview

``ImageRequest`` specifies what images to download, how to process it, set the request priority, and more.

```swift
let request = ImageRequest(
    url: URL(string: "http://example.com/image.jpeg"),
    processors: [.resize(size: imageView.bounds.size)],
    priority: .high,
    options: [.reloadIgnoringCacheData]
)
let response = try await pipeline.image(for: url)
```

## Creating a Request

A request is initialized with a resource address. It can be either a [`URL`](https://developer.apple.com/documentation/foundation/url) or [`URLRequest`](https://developer.apple.com/documentation/foundation/urlrequest).

```swift
// With `URL`
let request = ImageRequest(url: URL(string: "http://example.com/image.jpeg"))

// With `URLRequest`
let urlRequest = URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad)
let request = ImageRequest(urlRequest: urlRequest)
```

Alternatively, you can pass image data directly either using an asynchronous function or a Combine publisher.

```swift
ImageRequest(id: "image-id", data: {
    let (data, _) = try await URLSession.shared.data(for: URLRequest(url: localURL))
    return data
})
```

## Customizing a Request

In additional to a resource address, ``ImageRequest`` initializers like ``ImageRequest/init(url:processors:priority:options:userInfo:)`` accepts multiple other parameters. They can also be set using simple properties that are documented in the following section.

## Processors

Set ``ImageRequest/processors`` to apply one of the built-in processors that can be found in ``ImageProcessors`` namespace or a custom one.

```swift
request.processors = [.resize(size: imageView.bounds.size)]
```

> Tip: See <doc:image-processing> for more information on image processing.

## Priority

The execution priority of the request. The priority affects the order in which the image requests are executed. By default, `.normal`.

> Tip: You can change the priority of a running task using ``ImageTask/setPriority(_:)``.

```swift
request.priority = .high
```

## Options

By default, the pipeline makes full use of all of its caching layers. You can change this behavior using options. For example, you can ignore local caches using ``ImageRequest/Options-swift.struct/reloadIgnoringCachedData`` option.

```swift
request.options = [.reloadIgnoringCachedData]
```

Another useful cache policy is ``ImageRequest/Options-swift.struct/returnCacheDataDontLoad`` that allows you to existing cache data and fail if no cached data is available. For a complete list of options, see ``ImageRequest/Options-swift.struct``.

## User Info

``ImageRequest`` also supports custom options using ``ImageRequest/userInfo``. There are a couple of built-in options that are passed using ``ImageRequest/userInfo`` as well.

### Image ID

By default, a pipeline uses URLs as unique image identifiers for caching and task coalescing. You can override this behavior by providing an ``ImageRequest/UserInfoKey/imageIdKey`` instead. For example, you can use it to remove transient query parameters from the request.

```swift
var request = ImageRequest(url: URL(string: "http://example.com/image.jpeg?token=123"))
request.userInfo[.imageIdKey] = "http://example.com/image.jpeg"
)
```

### Thumbnails

To load a thumbnail instead of a full image, pass ``ImageRequest/ThumbnailOptions`` in the request ``ImageRequest/userInfo`` using ``ImageRequest/UserInfoKey/thumbnailKey``.

```swift
request.userInfo[.thumbnailKey] = ImageRequest.ThumbnailOptions(maxPixelSize: 400) 
```

This operation generates the thumbnail directly from the image data using [`CGImageSourceCreateThumbnailAtIndex`](https://developer.apple.com/documentation/imageio/1465099-cgimagesourcecreatethumbnailatin). It is more efficient and uses significantly less memory than ``ImageProcessors/Resize``, especially when generating thumbnails for large images. 

By default, it always generates a thumbnail. To use the thumbnail embedded in the image, see ``ImageRequest/ThumbnailOptions/createThumbnailFromImageAlways`` and ``ImageRequest/ThumbnailOptions/createThumbnailFromImageIfAbsent``.

### Scale

By default, ``ImagePipeline`` sets image [`scale`](https://developer.apple.com/documentation/uikit/uiimage/1624110-scale) to the scale of the screen. You can pass a custom scale to override it.

```swift
request.userInfo[.scaleKey] = 1.0
```
