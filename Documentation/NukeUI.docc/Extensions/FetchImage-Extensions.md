# ``NukeUI/FetchImage``

## Overview

``FetchImage`` is an observable object ([`ObservableObject`](https://developer.apple.com/documentation/combine/observableobject)) that allows you to manage the download of an image and observe the download status. It acts as a ViewModel that manages the image download state making it easy to add image loading to your custom SwiftUI views.

## Creating Custom Views

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
        .onDisappear { image.reset() }
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

## Topics

### Initializers

- ``init()``

### Loading Images

- ``load(_:)-9my9q``
- ``load(_:)-53ybw``
- ``load(_:)-6pey2``
- ``cancel()``
- ``reset()``

### State

- ``result``
- ``imageContainer``
- ``isLoading``
- ``progress-swift.property``

### Options

- ``priority``
- ``processors``
- ``pipeline``
- ``transaction``
