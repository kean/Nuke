# Nuke 14 Migration Guide

This guide eases the transition of the existing apps that use Nuke 13.x to the latest version of the framework.

> Nuke 14 is a work in progress. The guide is updated as the changes land.

## Minimum Requirements

The minimum supported platforms have been raised.

- iOS 16.0, tvOS 16.0, macOS 13.0, watchOS 9.0, visionOS 1.0
- Xcode 26.0
- Swift 6.2

Apps that need to support earlier OS versions can stay on Nuke 13.x, which continues to receive fixes.

## Removed Deprecated APIs

The APIs deprecated in Nuke 13 have been removed.

| Removed | Replacement |
|---|---|
| `ImagePipelineDelegate` | `ImagePipeline.Delegate` |
| `ImageRequest.imageId` | `ImageRequest.imageID` |
| `ImageRequest.UserInfoKey.imageIdKey` | `ImageRequest.imageID` |
| `ImageRequest.UserInfoKey.scaleKey` | `ImageRequest.scale` |
| `ImageRequest.UserInfoKey.thumbnailKey` | `ImageRequest.thumbnail` |
| `ImagePipeline.Configuration.maximumDecodedImageSize` | `ImageRequest.ThumbnailOptions` |
| `ImageDecodingContext.maximumDecodedImageSize` | `ImageRequest.ThumbnailOptions` |

The automatic downscaling implementation behind `maximumDecodedImageSize` was removed in Nuke 13, so setting it already had no effect. Use `ImageRequest.ThumbnailOptions` to control the decoded image size on a per-request basis instead.

## Removed `userInfo` from `ImageRequest` Initializers

The `userInfo` parameter, soft-deprecated in Nuke 13, is gone from the `ImageRequest` initializers. The options it used to carry now have dedicated type-safe properties, and `userInfo` itself remains available as a property for custom values.

```swift
// Before
let request = ImageRequest(url: url, userInfo: ["key": "value"])

// After
var request = ImageRequest(url: url)
request.userInfo = ["key": "value"]
```

## Removed Combine Support

The Combine APIs are gone. Use the Async/Await APIs instead.

| Removed | Replacement |
|---|---|
| `ImagePipeline.imagePublisher(with:)` | `ImagePipeline.image(for:)` or `ImagePipeline.imageTask(with:)` |
| `FetchImage.load(_:)` taking a `Publisher` | `FetchImage.load(_:)` taking an async closure |

```swift
// Nuke 13
cancellable = ImagePipeline.shared.imagePublisher(with: url)
    .sink(receiveCompletion: { _ in }, receiveValue: { response in
        imageView.image = response.image
    })

// Nuke 14
imageView.image = try await ImagePipeline.shared.image(for: url)
```

To observe progressively decoded previews, which the publisher used to emit as intermediate values, use `ImageTask.previews`.

`FetchImage` remains an `ObservableObject`, so observing it from SwiftUI is unchanged.

## Removed `ImageTask.Event.started`

`ImageTask.Event.started` is gone. It was never delivered to `ImageTask.events` – the pipeline reported it to the delegate directly – so it only ever existed for `ImagePipeline.Delegate`. The delegate now has a dedicated method instead.

```swift
// Nuke 13
func imageTask(_ task: ImageTask, didReceiveEvent event: ImageTask.Event, pipeline: ImagePipeline) {
    switch event {
    case .started: handleStart(task)
    case .progress, .preview, .finished: break
    }
}

// Nuke 14
func imageTaskDidStart(_ task: ImageTask, pipeline: ImagePipeline) {
    handleStart(task)
}
```

## `Float` to `CGFloat`

The public scale and size APIs now use `CGFloat`, matching the types you get from UIKit and SwiftUI.

| API | Nuke 13 | Nuke 14 |
|---|---|---|
| `ImageRequest.scale` | `Float` | `CGFloat` |
| `ImageRequest.ThumbnailOptions.init(maxPixelSize:)` | `Float` | `CGFloat` |

Literals continue to work as is. Remove the conversions if you had any:

```swift
// Nuke 13
request.scale = Float(traitCollection.displayScale)

// Nuke 14
request.scale = traitCollection.displayScale
```
