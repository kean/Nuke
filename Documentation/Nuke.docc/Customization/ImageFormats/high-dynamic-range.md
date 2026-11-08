# High Dynamic Range

Load HDR images and display them at their full brightness.

## Overview

HDR is opt-in, and it takes two settings: one to decode the image, and one to display it.

In SwiftUI, one modifier does both. Call it after the other `LazyImage` options, because it returns a plain view:

```swift
LazyImage(url: url)
    .priority(.high)
    .allowedDynamicRange(.high)
```

It applies to every `Image` in the view, including the ones in a custom `content` closure.

In UIKit and AppKit, set ``ImageRequest/dynamicRange`` on the request and `preferredImageDynamicRange` on the image view:

```swift
var request = ImageRequest(url: url)
request.dynamicRange = .high

imageView.preferredImageDynamicRange = .high
ImageLoader.load(request, into: imageView)
```

With `LazyImageView`, set `preferredImageDynamicRange` on its `imageView`.

HDR requires iOS 17, tvOS 17, macOS 14, watchOS 10, or visionOS 1. On earlier versions, a request for ``ImageRequest/DynamicRange-swift.enum/high`` decodes the standard image. watchOS decodes HDR, but it has no way to display it.

## Gain Maps

Most HDR photos, including the ones an iPhone takes and Ultra HDR JPEGs, are standard images with a *gain map* that says how much brighter each area gets. By default, the gain map is ignored. ``ImageRequest/DynamicRange-swift.enum/high`` applies it.

An image with no standard version, such as a 10-bit PQ HEIC or AVIF, decodes as HDR with either setting. With ``ImageRequest/DynamicRange-swift.enum/high``, it also skips decompression, which keeps it at 4 bytes per pixel instead of 8.

## How the Pipeline Treats HDR

- term **Decoding**: The image is decoded in full on the decoding queue, with `kCGImageSourceDecodeToHDR`, and the pipeline skips decompression. `preparingForDisplay()` goes back to the standard image when it finds a gain map, and the fallback draws in 8 bits per component.
- term **Thumbnails**: ``ImageRequest/thumbnail`` keeps HDR, which makes it the way to downscale an HDR image.
- term **Processors**: A request with ``ImageRequest/processors`` ignores ``ImageRequest/dynamicRange``. Processors draw in 8 bits per component, which would show as banding, so they start from the standard image, and the request shares its work and its cache entries with a standard one.
- term **Memory cache**: Each range has its own entry.
- term **Disk cache**: Both ranges read the same original data, and an HDR image is never encoded, because that would flatten it. With ``ImagePipeline/DataCachePolicy/storeEncodedImages``, the pipeline stores the original data instead. A thumbnail isn't stored, and it's generated from the original data. If a standard request already stored an encoded image under the key, an HDR request reads that one, and gets a standard image.
- term **Task coalescing**: The two ranges share a download, and decode separately.
- term **Previews and animations**: Progressive previews and animated images stay in the standard range.

## Simulators and macOS

A simulator can't apply a gain map, and `kCGImageSourceDecodeToHDR` returns a black image there, so on a simulator the pipeline decodes these images as standard. To see one in HDR, run on a device or a Mac.

On macOS, `NSImage` applies a gain map on its own when it's asked for a `CGImage`, so the pixels you read from a standard image can be brighter than SDR white.
