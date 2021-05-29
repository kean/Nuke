# Switching to Nuke from Kingfisher

Both frameworks appeared at roughly the same time in 2015. So they've been around almost as long as Swift has been.

Kingfisher was ["heavily inspired"](https://github.com/onevcat/Kingfisher/tree/1.0.0)
by [SDWebImage](https://github.com/SDWebImage/SDWebImage). In fact, many APIs directly match the APIs found in SDWebImage. The most recent versions
became better Swift citizens, but you can still find some Objective-C/SDWebImage
influences, e.g. `progressBlock` name.

Nuke, on the other hand, was designed from the ground up according to the
[Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/).

This document isn't a comparison between frameworks. It is aimed to help
you switch from Kingfisher to Nuke. This guide covers some basic scenarios
common across the frameworks.

## Image View Extensions

Both frameworks have `UIKit` and `AppKit` extensions to make it easy to load images into native images views while also facilitating cell reuse.

**Kingfisher**

```swift
imageView.kf.setImage(with: URL(string: "https://example.com/image.jpeg"))
```     

**Nuke**   

```swift
Nuke.loadImage(with: "https://example.com/image.jpeg", into: imageView)
```

With Nuke, you can pass `String`, `URL`, `URLRequest`, or `ImageRequest` into the `loadImage()` method.

> Learn more in ["Image View Extensions."](https://kean.blog/nuke/guides/image-view-extensions). There are a ton of customizations options available.


## Image Processing
    func imageProcessing() {
    Kingfisher
        let processor = DownsamplingImageProcessor(size: CGSize(width: 44, height: 44))
            |> RoundCornerImageProcessor(cornerRadius: 8)
        imageView.kf.setImage(
            with: URL(string: "https://example.com/image.jpeg"),
            options: [.processor(processor)]
        )

    Nuke
        let request = ImageRequest(
            url: URL(string: "https://example.com/image.jpeg"),
            processors: [
                ImageProcessors.Resize(size: CGSize(width: 44, height: 44)),
                ImageProcessors.RoundedCorners(radius: 8)
            ]
        )
        Nuke.loadImage(with: request, into: imageView)
    }


# Request Options
    func requestOptions() {
    Kingfisher
        imageView.kf.setImage(
            with: URL(string: "https://example.com/image.jpeg"),
            options: [
                .downloadPriority(10),
                .forceRefresh
            ]
        )

    Nuke
        let request = ImageRequest(
            url: URL(string: "https://example.com/image.jpeg"),
            priority: .high,
            options: [.reloadIgnoringCachedData]
        )
        Nuke.loadImage(with: request, into: imageView)
    }

## Loading Images Directly
    func loadingImagesDirectly() {
    Kingfisher
        func kingfisher() {
            guard let url = URL(string: "https://example.com/image.jpeg") else {
                return // KingfisherManager requires a non-optional URL
            }
            let task = KingfisherManager.shared.retrieveImage(with: url) { result in
                switch result {
                case .success(let result):
                    print("Fetched image: \(result.image)")
                case .failure(let error):
                    print("Failed with \(error)")
                }
            }
            task?.cancel()
        }

    Nuke
        func nuke() {
            let url = URL(string: "https://example.com/image.jpeg")
            let task = ImagePipeline.shared.loadImage(with: url) { result in
                switch result {
                case .success(let result):
                    print("Fetched image: \(result.image)")
                case .failure(let error):
                    print("Failed with \(error)")
                }
            }
            task.cancel()
            task.priority = .high // Change priority dynamically (Nuke-only)
        }
    }

## Caching
    func caching() {
    Kingfisher
        //
    Designed to work with a custom cache with no clear way to disable it


    Nuke
        //
    By default, is initialized with a native HTTP disk cache. Can be
    configured to work with a custom aggressive LRU disk cache.
        //
    Learn more in ["Caching."](https://kean.blog/nuke/guides/caching)
        ImagePipeline(configuration: .withURLCache) // Default cache
        ImagePipeline(configuration: .withDataCache) // Aggressive cache
    }

This guide only covered the most basic APIs. To learn more about Nuke,
please refer to the official website with the [comprehensive documentation](https://kean.blog/nuke/guides/welcome)
on every Nuke feature.
