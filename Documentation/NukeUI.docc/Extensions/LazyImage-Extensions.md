# ``NukeUI/LazyImage``

## Using LazyImage

The view is instantiated with a [`URL`](https://developer.apple.com/documentation/foundation/url) or an ``ImageRequest``.

```swift
struct ContainerView: View {
    var body: some View {
        LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    }
}
```

The view is called "lazy" because it loads the image only when it appears on the screen. And when it disappears, the current request automatically gets canceled. When the view reappears, the download picks up where it left off, thanks to [resumable downloads](https://kean.blog/post/resumable-downloads). 

> Tip: To change the `onDisappear` behavior, use ``LazyImage/onDisappear(_:)``.

Until the image loads, the view displays a standard placeholder that fills the available space, just like [AsyncImage](https://developer.apple.com/documentation/SwiftUI/AsyncImage) does. After the load completes successfully, the view updates to display the image.

![nukeui demo](nukeui-preview)

To gain more control over the loading process and how the image is displayed, ``LazyImage/init(url:transaction:content:)``, which takes a `content` closure that receives a ``LazyImageState``.

```swift
LazyImage(url: URL(string: "https://example.com/image.jpeg")) { state in
    if let image = state.image {
        image.resizable().aspectRatio(contentMode: .fill)
    } else if state.error != nil {
        Color.red // Indicates an error
    } else {
        Color.blue // Acts as a placeholder
    }
}
```

> Important: You can’t apply image-specific modifiers, like `resizable(capInsets:resizingMode:)`, directly to a `LazyImage`. Instead, apply them to the `Image` instance that your content closure gets when defining the view’s appearance.

When the image is loaded, it is displayed with no animation, which is a recommended option. If you add an animation, it's automatically applied when the image is downloaded, but not when it's retrieved from the memory cache. 

```swift
LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    .animation(.default)
```

`LazyImage` can be instantiated with an `ImageRequest` or configured using convenience modifiers.

```swift
LazyImage(request: ImageRequest(
    url: URL(string: "https://example.com/image.jpeg"),
    processors: [.resize(width: 44)]
))

LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    .processors([.resize(width: 44)])
    .priority(.high)
    .pipeline(customPipeline)
```

> Tip: ``LazyImage`` is built on top of ``FetchImage``. If you want even more control, you can use it directly instead.  

## Topics

### Initializers

- ``init(url:)``
- ``init(request:)``
- ``init(url:transaction:content:)``
- ``init(request:transaction:content:)``

### Cancellation

- ``onDisappear(_:)``

### Request Options

- ``priority(_:)``
- ``processors(_:)``
- ``pipeline(_:)``
