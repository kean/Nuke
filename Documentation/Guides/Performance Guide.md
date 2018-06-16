### Create `URL`s in a Background

`URL` initializer is expensive because it parses the input string. It might take more time than the call to `Nuke.loadImage(with:into)` itself. Make sure to create the `URL` objects in a background. For example, it might be a good idea to create `URL` when parsing JSON to create your model objects.


### Avoiding Decompression on the Main Thread

When you create `UIImage` object form data, the data doesn't get decoded immediately. It's decoded the first time it's used - for example, when you display the image in an image view. Decoding is a resource-intensive operation, if you do it on the main thread you might see dropped frames, especially for image formats like JPEG.

To prevent decoding happening on the main thread, Nuke perform it in a background for you. But for even better performance it's recommended to downsample the images. To do so create a request with a target view size:

```swift
ImageRequest(url: url, targetSize: CGSize(width: 640, height: 320), contentMode: .aspectFill)
```

> **Warning:** target size is in pixels!

> See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.


### Avoiding Excessive Cancellations

Don't cancel outstanding requests when it's not necessary. For instance, when reloading `UITableView` you might want to check if the cell that you are updating is not already loading the same image.


### Optimizing On-Disk Caching

Nuke comes with a `Foundation.URLCache` by default. It's [a great option](https://kean.github.io/post/image-caching) especially when you need a HTTP cache validation. However, it might be a little bit slow.

Cache lookup is a part of `URLSessionTask` flow which has some implications. The amount of concurrent `URLSessionTasks` is limited to 6 by Nuke (you can't just fire off an arbitrary number of concurrent HTTP requests). It means that if there are already 6 outstanding requests, you won't be able to check on-disk cache for the 7th request until one of the outstanding requests finishes.

In order to optimize on-disk caching you might want to use a third-party caching library. Check out [Third Party Libraries: Using Other Caching Libraries](https://github.com/kean/Nuke/blob/master/Documentation/Guides/Third%20Party%20Libraries.md#using-other-caching-libraries) for an example.
