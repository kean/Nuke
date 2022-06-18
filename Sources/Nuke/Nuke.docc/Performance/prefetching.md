# Prefetching

Loading data ahead of time in anticipation of its use (prefetching) is a great way to improve user experience. It's especially effective for images; it can give users an impression that there is no networking and the images are just magically always there.

## UICollectionView

Starting with iOS 10, it became easy to implement prefetching in a `UICollectionView` thanks to the [`UICollectionViewDataSourcePrefetching`](https://developer.apple.com/documentation/uikit/uicollectionviewdatasourceprefetching) API. All you need to do is set [`isPrefetchingEnabled`](https://developer.apple.com/documentation/uikit/uicollectionview/1771771-isprefetchingenabled) to `true` and set a [`prefetchDataSource`](https://developer.apple.com/documentation/uikit/uicollectionview/1771768-prefetchdatasource).

```swift
final class PrefetchingDemoViewController: BaseDemoViewController {
    let prefetcher = ImagePrefetcher()

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView?.isPrefetchingEnabled = true
        collectionView?.prefetchDataSource = self
    }
}

extension PrefetchingDemoViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView,
                        prefetchItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.map { photos[$0.row] }
        prefetcher.startPrefetching(with: urls)
    }

    func collectionView(_ collectionView: UICollectionView,
                        cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.map { photos[$0.row] }
        prefetcher.startPrefetching(with: urls)
    }
}
```

This code sample comes straight from [Nuke Demo](https://github.com/kean/NukeDemo). So does the following screenshot.

There are 32 items on the screen (the last row is partially visible). When you open it for the first time, the prefetch API asks the app to start prefetching for indices `[32-55]`. As you scroll, the prefetch "window" changes. You receive `cancelPrefetchingForItemsAt` calls for items no longer in the prefetch window.

> `UICollectionView` offers no customization options. If you want to have more control, check out [Preheat](https://github.com/kean/Preheat). I deprecated it, but you can find it helpful nevertheless.

When the user goes to another screen, you can either cancel all the prefetching tasks (but then you'll need to figure out a way to restart them when the user comes back) or, with [Nuke 9.4.0](https://github.com/kean/Nuke/releases/tag/9.4.0), you can simply pause them.

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
}```

> Starting with [Nuke 9.5.0](https://github.com/kean/Nuke/releases/tag/9.5.0), you can also change the prefetcher priority. For example, when the user goes to another screen that also has image prefetching, you can lower it to `.veryLow`. This way, the prefetching will continue for both screens, but the top screen will have priority.

## ImagePrefetcher
 
You typically create one ``ImagePrefetcher`` per screen.

```swift
let prefetcher = ImagePrefetcher()

public final class ImagePrefetcher {
    public init(pipeline: ImagePipeline = ImagePipeline.shared,
                destination: Destination = .memoryCache,
                maxConcurrentRequestCount: Int = 2)
}
```

To start prefetching, call ``ImagePrefetcher/startPrefetching(with:)`` method. When you need the same image later to display it, simply use the ``ImagePipeline`` or view extensions to load the image. The pipeline will take care of coalescing the requests for new without starting any new downloads.

```swift
public extension ImagePrefetcher {
    func startPrefetching(with urls: [URL])
    func startPrefetching(with requests: [ImageRequest])

    func stopPrefetching(with urls: [URL])
    func stopPrefetching(with requests: [ImageRequest])
    func stopPrefetching()
}
```

The prefetcher automatically cancels all of the outstanding tasks when deallocated. All ``ImagePrefetcher`` methods are thread-safe and are optimized to be used even from the main thread during scrolling.

> Important: Keep in mind that prefetching takes up users' data and puts extra pressure on CPU and memory! To reduce the CPU and memory usage, you have an option to choose only the disk cache as a prefetching destination: `ImagePrefetcher(destination: .diskCache)`. It doesn't require image decoding and processing and therefore uses less CPU. The images are stored on disk, so they also take up less memory. This policy doesn't work with ``ImagePipeline/Configuration-swift.struct/DataCachePolicy-swift.enum/storeEncodedImages`` cache policy and other policies that affect `loadData()`. 

With [Nuke 9.4.0](https://github.com/kean/Nuke/releases/tag/9.4.0), you can now also pause prefetching (``ImagePrefetcher/isPaused``), which is useful when the user navigates to a different screen. And starting with [Nuke 9.5.0](https://github.com/kean/Nuke/releases/tag/9.5.0), you can also change the prefetcher priority. For example, when the user goes to another screen, you can lower it to `.veryLow`.

```swift
public extension ImagePrefetcher {
    var isPaused: Bool = false
    var priority: ImageRequest.Priority = .low
}
```
