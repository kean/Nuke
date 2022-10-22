# ``NukeUI/LazyImage``

## Using LazyImage

The view is instantiated with a `URL` or an ``ImageRequest``.

```swift
struct ContainerView: View {
    var body: some View {
        LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    }
}
```

The view is called "lazy" because it loads the image from source only when it appears on the screen. And when it disappears, the current request automatically gets canceled. When the view reappears, the download picks up where it left off, thanks to [resumable downloads](https://kean.blog/post/resumable-downloads). 

The view doesn't know the size of the image before it downloads it. Thus, you must specify the view size before loading the image. By default, the image will resize preserving the aspect ratio to fill the available space. You can change this behavior by passing a different resizing mode.

```swift
LazyImage(url: URL(string: "https://example.com/image.jpeg"), resizingMode: .center)
    .frame(height: 300)
```

> **Important**. You can’t apply image-specific modifiers, like `aspectRatio()`, directly to a `LazyImage`.

Until the image loads, the view displays a standard placeholder that fills the available space, just like [AsyncImage](https://developer.apple.com/documentation/SwiftUI/AsyncImage) does. After the load completes successfully, the view updates to display the image.

![nukeui demo](nukeui-preview)

You can also specify a custom placeholder, a view to be displayed on failure, or even show a download progress.

```swift
LazyImage(url: $0) { state in
    if let image = state.image {
        image // Displays the loaded image
    } else if state.error != nil {
        Color.red // Indicates an error
    } else {
        Color.blue // Acts as a placeholder
    }
}
```

When the image is loaded, it is displayed with a default animation. You can change it using a custom `animation` option.

```swift
LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    .animation(nil) // Disable all animations
```

You can pass a complete `ImageRequest` as a source, but you can also configure the download via convenience modifiers.

```swift
LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    .processors([ImageProcessors.Resize(width: 44)])
    .priority(.high)
    .pipeline(customPipeline)
```

> ``LazyImage`` is built on top of ``FetchImage``. If you want even more control, you can use it directly instead.  

You can also monitor the status of the download.

```swift
LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    .onStart { print("Task started \($0)") }
    .onProgress { ... }
    .onSuccess { ... }
    .onFailure { ... }
    .onCompletion { ... }
```

And if some API isn't exposed yet, you can always access the underlying `ImageView` instance.

```swift
LazyImage(url: URL(string: "https://example.com/image.jpeg"))
    .onCreated { view in 
        view.videoGravity = .resizeAspect
    }
```

## Topics

### Initializers

- ``init(url:resizingMode:)``
- ``init(request:resizingMode:)``
- ``init(url:content:)``
- ``init(request:content:)``

### Accessing Underlying Views

- ``onCreated(_:)``

### Cancellation

- ``onDisappear(_:)``

### Request Options

- ``priority(_:)``
- ``processors(_:)``
- ``pipeline(_:)``

### Callbacks

- ``onStart(_:)``
- ``onPreview(_:)``
- ``onProgress(_:)``
- ``onSuccess(_:)``
- ``onFailure(_:)``
- ``onCompletion(_:)``

### Deprecated

- ``init(source:resizingMode:)``
- ``init(source:content:)``
