# Loading Data

Learn how pipeline loads data.

## Overview

``DataLoader`` uses [`URLSession`](https://developer.apple.com/reference/foundation/nsurlsession) to load image data. The data is cached on disk using [`URLCache`](https://developer.apple.com/reference/foundation/urlcache), which by default is initialized with a memory capacity of 0 MB (Nuke only stores processed images in memory) and disk capacity of 150 MB.

> Tip: See [Image Caching](https://kean.blog/post/image-caching) to learn more about HTTP cache. To learn more about caching in Nuke and how to configure it, see <doc:caching>.

The `URLSession` class natively supports the following URL schemes: `data`, `file`, `ftp`, `http`, and `https`.

The default ``DataLoader`` works great for most situation, but if you need to provide a custom networking layer, you can using a ``DataLoading`` protocol. See also, [Alamofire Plugin](https://github.com/kean/Nuke-Alamofire-Plugin).

## Resumable Downloads

If the data task is terminated when the image is partially loaded (either because of a failure or a cancellation), the next load will resume where the previous left off. Resumable downloads require the server to support [HTTP Range Requests](https://developer.mozilla.org/en-US/docs/Web/HTTP/Range_requests). Nuke supports both validators: `ETag` and `Last-Modified`. Resumable downloads are enabled by default. You can learn more in ["Resumable Downloads"](https://kean.blog/post/resumable-downloads).

## Topics

### Data Loader

- ``DataLoading``
- ``DataLoader``
- ``Cancellable``

### Monitoring Data Events

- ``DataLoaderObserving``
- ``DataTaskEvent``

