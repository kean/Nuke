# ``Nuke/ImageRequest``

## Image Processing

Set ``ImageRequest/processors`` to apply one of the built-in processors that can be found in ``ImageProcessors`` namespace or a custom one.

```swift
request.processors = [.resize(width: 320)]
```

> Tip: See <doc:image-processing> for more information on image processing.

## Cache Policy Options

``ImageRequest/Options-swift.struct`` is an `OptionSet` that controls how the pipeline interacts with its cache layers. By default, all caching is active.

```swift
// Always reload from the network, ignoring Nuke's caches
let request = ImageRequest(url: url, options: [.reloadIgnoringCachedData])

// Only return a cached result; don't go to the network
let cachedRequest = ImageRequest(url: url, options: [.returnCacheDataDontLoad])
```

## Topics

### Initializers

- ``init(url:processors:priority:options:userInfo:)``
- ``init(urlRequest:processors:priority:options:userInfo:)``
- ``init(id:data:processors:priority:options:userInfo:)``
- ``init(stringLiteral:)``

### Options

- ``processors``
- ``priority-swift.property``
- ``options-swift.property``
- ``imageID``
- ``scale``
- ``thumbnail``
- ``userInfo``

### Nested Types

- ``Priority-swift.enum``
- ``Options-swift.struct``
- ``ThumbnailOptions``
- ``UserInfoKey``

### Instance Properties

- ``urlRequest``
- ``url``
- ``description``
