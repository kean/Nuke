# Integration With Third-Party Libraries

### Using Other Networking Libraries

By default, Nuke uses a `Foundation.URLSession` for all the networking. Apps may have their own network layer they may wish to use instead.

Nuke already has an [Alamofire plugin](https://github.com/kean/Nuke-Alamofire-Plugin) that allows you to load image data using [Alamofire.SessionManager](https://github.com/Alamofire/Alamofire). If you want to use Nuke with Alamofire simply follow the plugin's docs.

If you'd like to use some other networking library or use your own custom code all you need to do is implement `Nuke.DataLoading` protocol which consists of a single method:

```swift
/// Loads data.
public protocol DataLoading {
    /// - parameter didReceiveData: Can be called multiple times if streaming
    /// is supported.
    /// - parameter completion: Must be called once after all (or none in case
    /// of an error) `didReceiveData` closures have been called.
    func loadData(with request: URLRequest,
                  didReceiveData: @escaping (Data, URLResponse) -> Void,
                  completion: @escaping (Error?) -> Void) -> Cancellable
}
```

You can use [Alamofire plugin](https://github.com/kean/Nuke-Alamofire-Plugin) as a starting point.

### Using Other Caching Libraries

By default, Nuke uses a `Foundation.URLCache` which is a part of Foundation URL Loading System. However sometimes built-in cache might not be performant enough, or might not fit your needs.

> See [Image Caching Guide](https://kean.github.io/post/image-caching) to learn more about URLCache, HTTP caching, and more

> See [Performance Guide: On-Disk Caching](https://github.com/kean/Nuke/blob/9.1.0/Documentation/Guides/performance-guide.md#on-disk-caching) for more info

Nuke can be used with any third party caching library.

1) Add conformance to `DataCaching` protocol:

```swift
extension DFCache: DataCaching {
    public func cachedData(for key: String) -> Data? {
        return self.cachedData(forKey: key)
    }

    public func storeData(_ data: Data, for key: String) {
        self.store(data, forKey: key)
    }
}
```

2) Configure `ImagePipeline` to use a new `DFCache`:

```swift
ImagePipeline.shared = ImagePipeline {
    let conf = URLSessionConfiguration.default
    conf.urlCache = nil // Disable native URLCache
    $0.dataLoader = DataLoader(configuration: conf)

    $0.dataCache = DFCache(name: "com.github.kean.Nuke.DFCache", memoryCache: nil)
}
```

> As of Nuke 7, there is now a built-in agressive disk cache available. See `DataCache` for more info.

### Integrating with Vector Images Libraries

To render SVG, consider using [SwiftSVG](https://github.com/mchoe/SwiftSVG), [SVG](https://github.com/SVGKit/SVGKit), or other frameworks. Here is an example of `SwiftSVG` being used to render vector images:

```swift
ImageDecoderRegistry.shared.register { context in
    // Replace this with whatever works for. There are no magic numbers
    // for SVG like are used for other binary formats, it's just XML.
    let isSVG = context.urlResponse?.url?.absoluteString.hasSuffix(".svg") ?? false
    return isSVG ? ImageDecoders.Empty() : nil
}

let url = URL(string: "https://upload.wikimedia.org/wikipedia/commons/9/9d/Swift_logo.svg")!
ImagePipeline.shared.loadImage(with: url) { [weak self] result in
    guard let self = self, let data = try? result.get().container.data else {
        return
    }
    // You can render image using whatever size you want, vector!
    let targetBounds = CGRect(origin: .zero, size: CGSize(width: 300, height: 300))
    let svgView = UIView(SVGData: data) { layer in
        layer.fillColor = UIColor.orange.cgColor
        layer.resizeToFit(targetBounds)
    }
    self.view.addSubview(svgView)
    svgView.bounds = targetBounds
    svgView.center = self.view.center
}
```
