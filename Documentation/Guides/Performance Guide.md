### Create `URL`s in a Background

`URL` initializer is expensive because it needs to parse the input strings. It might take more time than the call to `Nuke.loadImage(with:into)` itself. Make sure to create the `URL` objects somewhere in a background. For example, it might be a good idea to create `URL` when parsing JSON to create your model objects.


### Avoiding Decompression on the Main Thread

By default each `Request` comes with a `Decompressor` which forces compressed image data to be drawn into a bitmap. This happens in a background to [avoid decompression sickness](https://www.cocoanetics.com/2011/10/avoiding-image-decompression-sickness/) on the main thread.


### Avoiding High Memory Usage

Displaying images takes a lot of memory. Here's a couple of tips to reduce memory usage when using Nuke:

- The loaded images should ideally be the same size as the image views (taking retina into account). If the loaded images have a resolution which is higher than necessary make sure to resize them. Nuke has a built-in way to resize images:

```swift
var request = Request(url: url)
let targetSize = Decompressor.targetSize(for: view)
request.processor = AnyProcessor(Decompressor(targetSize: targetSize, contentMode: .aspectFill))
```

- Reduce the `costLimit` and/or `countLimit` of `Cache.shared`. In most cases having a single global memory cache is what you want. However Nuke also allows you to have multiple memory caches (for e.g. one cache per screen). To do that create a separate `Nuke.Manager` instance per screen, each should be initialized with its own cache.


### Avoiding Excessive Cancellations

Don't cancel outstanding requests when it's not necessary. For instance, when reloading `UITableView` you might want to check if the cell that you are updating is not already loading the same image.


### Optimizing On-Disk Caching

Nuke comes with a `Foundation.URLCache` by default. It's [a great option](https://kean.github.io/post/image-caching) especially when you need a HTTP cache validation. However, it might be a little bit slow.

Cache lookup is a part of `URLSessionTask` flow which has some implications. The amount of concurrent `URLSessionTasks` is limited to 8 by Nuke (you can't just fire off an arbitrary number of concurrent HTTP requests). It means that if there are already 8 outstanding requests, you won't be able to check on-disk cache for the 9th request until one of the outstanding requests finishes.

In order to optimize on-disk caching you might want to use a third-party caching library. Check out [Third Party Libraries: Using Other Caching Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries) for an example.
