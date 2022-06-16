# Combine

``ImagePublisher`` starts a new ``ImageTask`` when a subscriber is added and delivers the results to the subscriber. If the requested image is available in the memory cache, the value is delivered immediately. When the subscription is canceled, the task also gets canceled.

> Tip: If you need to support earlier iOS versions, check out [RxNuke](https://github.com/kean/RxNuke) - RxSwift extensions for Nuke

## Image Publisher

To create ``ImagePublisher``, use the following API added to ``ImagePipeline``:

```swift
public extension ImagePipeline {
    func imagePublisher(with request: ImageRequestConvertible) -> ImagePublisher
}
```

A basic example where we load an image and display the result on success:

```swift
cancellable = pipeline.imagePublisher(with: url)
    .sink(receiveCompletion: { _ in /* Ignore errors */ },
          receiveValue: { imageView.image = $0.image })
```

## Displaying Images

So you created a custom publisher by combining a couple of operators, how do you use it to display the image? ``FetchImage`` provides a simple way to display the resuling image.

```swift
let image = FetchImage()
let publisher = pipeline.imagePublisher(with: "https://example.com/image.jpeg")
image.load(publisher)
```

## Use Cases

There are many scenarios in which you can find Combine useful. Here are some of them.

### Low Resolution to High

Let's say you want to show a user a high-resolution image that takes a while to loads. You can show a spinner while the high-resolution image is downloaded, but you can improve the user experience by quickly downloading and displaying a thumbnail.

You can implement it using `append` operator. This operator results in a serial execution. It starts a thumbnail request, waits until it finishes, and only then starts a request for a high-resolution image.

```swift
let lowResImage = pipeline.imagePublisher(with: lowResUrl).orEmpty
let highResImage = pipeline.imagePublisher(with: highResUrl).orEmpty

cancellable = lowResImage.append(highResImage)
    .sink(receiveCompletion: { _ in /* Ignore errors */ },
          receiveValue: { imageView.image = $0.image })
```

> `orEmpty` is a custom property that catches the errors and immediately completes the publishes instead.

```swift
public extension Publisher {
    var orEmpty: AnyPublisher<Output, Never> {
        catch { _ in Empty<Output, Never>() }.eraseToAnyPublisher()
    }
}
```

### Load the First Available

Let's say you have multiple URLs for the same image. For example, you uploaded the image from the camera to the server; you have the image stored locally. When you display this image, it would be beneficial to first load the local URL, and if that fails, try to download from the network.

This use case is very similar to [Going From Low to High Resolution](#going-from-low-to-high-resolution), except for the addition of the `first()` operator that stops the execution when the first value is received.

```swift
let localImage = pipeline.imagePublisher(with: localUrl).orEmpty
let networkImage = pipeline.imagePublisher(with: networkUrl).orEmpty

cancellable = localImage.append(networkImage)
    .first()
    .sink(receiveCompletion: { _ in /* Ignore errors */ },
          receiveValue: { imageView.image = $0.image })
```

### Load Multiple Images

Let's say you want to load two icons for a button, one icon for a `.normal` state, and one for a `.selected` state. You want to update the button, only when both icons are fully loaded. This can be achieved using a `combine` operator.

```swift
let iconImage = pipeline.imagePublisher(with: iconUrl)
let iconSelectedImage = pipeline.imagePublisher(with: iconSelectedUrl)

cancellable = iconImage.combineLatest(iconSelectedImage)
    .sink(receiveCompletion: { _ in /* Ignore errors */ },
          receiveValue: { icon, iconSelected in
            button.isHidden = false
            button.setImage(icon.image, for: .normal)
            button.setImage(iconSelected.image, for: .selected)
         })
```

Notice there is no `orEmpty` in this example since we want both requests to succeed.

### Validate Stale Image

Let's say you want to show the user a stale image stored in disk cache (`Foundation.URLCache`) while you go to the server to validate if the image is still fresh. It can be implemented using the same `append` operator that we covered [previously](#going-from-low-to-high-resolution).

```swift
let cacheRequest = URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad)
let networkRequest = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy)

let cachedImage = pipeline.imagePublisher(with: ImageRequest(urlRequest: cacheRequest)).orEmpty
let networkImage = pipeline.imagePublisher(with: ImageRequest(urlRequest: networkRequest)).orEmpty

cancellable = cachedImage.append(networkImage)
    .sink(receiveCompletion: { _ in /* Ignore errors */ },
          receiveValue: { imageView.image = $0.image })
```

> See ["Image Caching"](https://kean.blog/post/image-caching) to learn more about HTTP cache.
{:.info}

### Low Data Mode

Starting with iOS 13, the iOS users can enable "Low Data Mode" in system settings. One of the ways the apps can handle it is to use resources that take less network bandwidth. Combine makes it easy to implement.

```swift
// Create the original image request and prevent it from going through
// when "Low Data Mode" is enabled in the iOS settings.
var urlRequest = URLRequest(url: URL(string: "https://example.com/high-quality.jpeg")!)
urlRequest.allowsConstrainedNetworkAccess = false
let request = ImageRequest(urlRequest: urlRequest)

// Catch the "constrained" network error and provide a fallback resource
// that uses less network bandwidth.
let image = pipeline.imagePublisher(with: request).tryCatch { error -> ImagePublisher in
    guard (error.dataLoadingError as? URLError)?.networkUnavailableReason == .constrained else {
        throw error
    }
    return pipeline.imagePublisher(with: URL(string: "https://example.com/low-quality.jpeg"))
}

cancellable = image.sink(receiveCompletion: { result in
    // Handle error
}, receiveValue: {
    imageView.image = $0.image
})
```

> Tip: Learn more about Low Data Mode in [WWDC2019: Advances in Networking, Part 1](https://developer.apple.com/videos/play/wwdc2019/712/).
