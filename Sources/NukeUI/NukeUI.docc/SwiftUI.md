# SwiftUI

Nuke provides first-class SwiftUI support via two components:

- `LazyImage` (a View) which is part of the [NukeUI](https://github.com/kean/NukeUI) package
- ``FetchImage`` (a ViewModel) which is part of Nuke

## LazyImage

`LazyImage` which is part of the [NukeUI](https://github.com/kean/NukeUI) package that should be installed separately.

`LazyImage` uses [Nuke](https://github.com/kean/Nuke) for loading images and has many customization options. But it's not just that. It also supports progressive images, it has GIF support powered by [Gifu](https://github.com/kaishin/Gifu) and can even play short videos, which is [a much more efficient](https://web.dev/replace-gifs-with-videos/) to display animated images.

```swift
struct ProfileView: View {
    var body: some View {
        LazyImage(source: "https://example.com/image.jpeg")
    }
}
```

You can learn more about `LazyImage` in the [NukeUI](https://github.com/kean/NukeUI) repo.

## FetchImage

### Custom Image View

While `LazyImage` is part of a separate [package](https://github.com/kean/NukeUI), the core framework contains a ``FetchImage`` class. You can think of it as a ViewModel for your views.

```swift
struct ImageView: View {
    let url: URL

    @StateObject private var image = FetchImage()

    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray)
            image.view?
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        }
        .onAppear { image.load(url) }
        .onChange(of: url) { image.load($0) }
        .onDisappear(perform: image.reset)
    }
}
```

> Important: In iOS 13, use `@ObservedObject`. Keep in mind that it doesn't own the object.

### ViewModel

``FetchImage`` is an observable object (`ObservableObject`) that allows you to manage the download of an image and observe the download status.

```swift
public final class FetchImage: ObservableObject, Identifiable {

    /// Returns the current fetch result.
    @Published public private(set)
    var result: Result<ImageResponse, ImagePipeline.Error>?

    /// Returns the fetched image.
    ///
    /// - note: In case pipeline has `isProgressiveDecodingEnabled` option enabled
    /// and the image being downloaded supports progressive decoding, the `image`
    /// might be updated multiple times during the download.
    @Published public private(set)
    var image: UIImage?

    /// Returns `true` if the image is being loaded.
    @Published public private(set)
    var isLoading: Bool = false

    /// The progress of the image download.
    @Published public private(set)
    var progress = Progress()
}
```

### List

Usage with a list:

```swift
struct DetailsView: View {
    var body: some View {
        List(imageUrls, id: \.self) {
            ImageView(url: $0)
                .frame(height: 200)
        }
    }
}
```

``FetchImage`` gives you full control over how to manage the download and how to display the image. For example, if you want the download to continue when the view leaves the screen, change the appearance callbacks accordingly.

```swift
struct ImageView: View {
    let url: URL

    @StateObject private var image = FetchImage()

    var body: some View {
        // ...
        .onAppear {
            image.priority = .normal
            image.load(url)
        }
        .onDisappear {
            image.priority = .low
        }
    }
}
```

### Animations

```swift
struct ImageView: View {
    let url: URL

    @StateObject private var image = FetchImage()

    var body: some View {
        // ... create image view 
        .onAppear {
            // Ensure that memory cache lookup is performed without animations
            withoutAnimation {
                image.load(url)
            }
        }
        .onDisappear(perform: image.reset)
        .animation(.default)
    }
}

private func withoutAnimation(_ closure: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    withTransaction(transaction, closure)
}
```

### Grid

`ImageView` defined earlier can also be used in grids.

```swift
struct GridExampleView: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                let side = geometry.size.width / 4
                let item = GridItem(.fixed(side), spacing: 2)
                LazyVGrid(columns: Array(repeating: item, count: 4), spacing: 2) {
                    ForEach(demoPhotosURLs.indices) {
                        ImageView(url: demoPhotosURLs[$0])
                            .frame(width: side, height: side)
                            .clipped()
                    }
                }
            }
        }
    }
}
```

> To see grid in action, check out the [demo project](https://github.com/kean/NukeDemo).

### Combine

If you use Combine support (``ImagePublisher``) to create a custom image publisher, ``FetchImage`` provides a simple way to display the resuling image.

```swift
let image = FetchImage()
let publisher = pipeline.imagePublisher(with: "https://example.com/image.jpeg")
image.load(publisher)
```
