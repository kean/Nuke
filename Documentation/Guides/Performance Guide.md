### Create `URL`s in a Background

`URL` initializer is quite expensive (parses string's components) and might take more time as an actual call to `Nuke.loadImage(with:into)`. Make sure that you create those `URL`s in a background. Creating objects from JSON would be a good place.

### Decompression

By default each `Request` comes with a `Decompressor` which forces compressed image data to be drawn into a bitmap. This happens in a background to [avoid decompression sickness](https://www.cocoanetics.com/2011/10/avoiding-image-decompression-sickness/) on the main thread.

### Avoid excessive cancellations

Don't cancel outstanding requests when it's not necessary. For instance, when reloading `UITableView` you might want to check if the cell that you are updating is not already loading the same image.

### Cancel requests in `UICollectionView` / `UITableView`

You can implement `didEndDisplaying:forItemAt:` method to cancel the requests as soon as the cell goes off screen:

```swift
func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
    Nuke.cancelRequest(for: cell.imageView)
}
```

### On-Disk Caching

Nuke comes with a `Foundation.URLCache` by default. It's [a great option](https://kean.github.io/blog/image-caching) especially when you need a HTTP cache validation. However, it might be a little bit slow.

Cache lookup is a part of `URLSessionTask` flow which has some implications. The amount of concurrent `URLSessionTasks` is limited to 8 by Nuke (you can't just fire off an arbitrary number of concurrent HTTP requests). It means that if there are already 8 outstanding requests, you won't be able to check on-disk cache for the 9th request until one of the outstanding requests finishes.

In order to optimize on-disk caching you might want to use a third-party caching library. It's easy to integrate way using `DataCaching` protocol provided by Nuke. Check out demo project for an example.

### Rate Limiting Requests

There is [a known problem](https://github.com/kean/Nuke/issues/59) with `URLSession` that it gets trashed pretty easily when you resume and cancel `URLSessionTasks` at a very high rate (say, scrolling a large collection view with images). Some frameworks combat this problem by simply never cancelling `URLSessionTasks` which are already in `.running` state. This is not an ideal solution, because it forces users to wait for cancelled requests for images which might never appear on the display.

Nuke has a better, classic solution for this problem - it introduces a new `RateLimiter` class which limits the rate at which `URLSessionTasks` are created. `RateLimiter` uses a [token bucket](https://en.wikipedia.org/wiki/Token_bucket) algorithm. The implementation supports quick bursts of requests which can be executed without any delays when "the bucket is full". This is important to prevent the rate limiter from affecting "normal" requests flow. `RateLimiter` is enabled by default.

You can see `RateLimiter` in action in a new `Rate Limiter Demo` added in the sample project.

### Resizing Images

Resizing (and cropping) images might help both in terms of [image drawing performance](https://developer.apple.com/library/content/qa/qa1708/_index.html) and memory usage.
