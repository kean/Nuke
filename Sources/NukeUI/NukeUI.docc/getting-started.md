# Getting Started

Learn how to use views provided by NukeUI.


## Overview

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

If you use Combine support (``ImagePublisher``) to create a custom image publisher, ``FetchImage`` provides a simple way to display the resulting image.

```swift
let image = FetchImage()
let publisher = pipeline.imagePublisher(with: "https://example.com/image.jpeg")
image.load(publisher)
```
