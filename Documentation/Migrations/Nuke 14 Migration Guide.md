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
