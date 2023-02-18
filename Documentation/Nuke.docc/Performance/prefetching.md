# Prefetching

Learn how to prefetch images to improve user experience.

## Overview

Loading data ahead of time in anticipation of its use ([prefetching](https://en.wikipedia.org/wiki/Prefetching)) is a great way to improve user experience. It's especially effective for images; it can give users an impression that there is no networking and the images are just magically always there.

## UICollectionView

Starting with iOS 10, it became easy to implement prefetching in a `UICollectionView` thanks to the [`UICollectionViewDataSourcePrefetching`](https://developer.apple.com/documentation/uikit/uicollectionviewdatasourceprefetching) API. All you need to do is set [`isPrefetchingEnabled`](https://developer.apple.com/documentation/uikit/uicollectionview/1771771-isprefetchingenabled) to `true` and set a [`prefetchDataSource`](https://developer.apple.com/documentation/uikit/uicollectionview/1771768-prefetchdatasource).

```swift
final class PrefetchingDemoViewController: UICollectionViewController {
    private let prefetcher = ImagePrefetcher()
    private var photos: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView?.isPrefetchingEnabled = true
        collectionView?.prefetchDataSource = self
    }
}

extension PrefetchingDemoViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.map { photos[$0.row] }
        prefetcher.startPrefetching(with: urls)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.map { photos[$0.row] }
        prefetcher.stopPrefetching(with: urls)
    }
}
```

> Warning: If you are using any of the processors when displaying the images, e.g. ``ImageProcessors/Resize``, you need to use the same processors for prefetching. Otherwise, the prefetcher will bitmap and cache the original image, defeating the main purpose of prefetching to get images fully ready for display before the user even sees them.   

This code sample comes straight from [Nuke Demo](https://github.com/kean/NukeDemo).

Let's say, there are 32 items on the screen (the last row is partially visible). When you open it for the first time, the prefetch API asks the app to start prefetching for indices `[32-55]`. As you scroll, the prefetch "window" changes. You receive `cancelPrefetchingForItemsAt` calls for items no longer in the prefetch window.

When the user goes to another screen, you can either cancel all the prefetching tasks (but then you'll need to figure out a way to restart them when the user comes back) or, with you can also pause them.

```swift
override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    prefetcher.isPaused = false
}

override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)

    // When you pause, the prefetcher will finish outstanding tasks
    // (by default, there are only 2 at a time), and pause the rest.
    prefetcher.isPaused = true
}
```

> Tip: Starting with [Nuke 9.5.0](https://github.com/kean/Nuke/releases/tag/9.5.0), you can also change the prefetcher priority. For example, when the user goes to another screen that also has image prefetching, you can lower it to `.veryLow`. This way, the prefetching will continue for both screens, but the top screen will have priority.

## ImagePrefetcher
 
You typically create one ``ImagePrefetcher`` per screen.

To start prefetching, call ``ImagePrefetcher/startPrefetching(with:)-718dg`` method. When you need the same image later to display it, simply use the ``ImagePipeline`` or view extensions to load the image. The pipeline will take care of coalescing the requests for new without starting any new downloads:

- ``ImagePrefetcher/startPrefetching(with:)-718dg``
- ``ImagePrefetcher/stopPrefetching(with:)-8cdam``
- ``ImagePrefetcher/stopPrefetching()``

The prefetcher automatically cancels all of the outstanding tasks when deallocated. All ``ImagePrefetcher`` methods are thread-safe and are optimized to be used even from the main thread during scrolling.

> Important: Prefetching takes up users' data and puts extra pressure on CPU and memory. To reduce the CPU and memory usage, you have an option to choose only the disk cache as a prefetching destination: ``ImagePrefetcher/Destination/diskCache``. It doesn't require image decoding and processing and therefore uses less CPU. The images are stored on disk, so they also take up less memory. This policy doesn't work with ``ImagePipeline/DataCachePolicy/storeEncodedImages`` cache policy and other policies that affect `loadData()`. 

