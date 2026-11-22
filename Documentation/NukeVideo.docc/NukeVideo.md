# ``NukeVideo``

Decoding and playback for short videos.

## Overview

A short, silent, looping MP4 is a fraction of the size of the GIF it replaces, and the hardware decodes it. `NukeVideo` lets the pipeline load one the way it loads an image.

Register ``Nuke/ImageDecoders/Video`` with `ImageDecoderRegistry` to enable it. It recognizes MP4, M4V, and QuickTime files and passes on anything else. It returns an ordinary `ImageContainer`: the image is the first frame, a still any view can display, and `userInfo[.videoAssetKey]` is an `AVAsset` that reads the downloaded data, so a player never downloads the file again. ``VideoPlayerView`` plays it, muted and on a loop.

Keep the original data in the disk cache, with `.storeOriginalData` or `.automatic`: under `.storeEncodedImages`, the pipeline stores a JPEG of the first frame instead, and the video comes back from the disk as a still. See [Supported Image Formats](https://kean-docs.github.io/nuke/documentation/nuke/supported-image-formats#Video).

The decoder isn't available on watchOS or visionOS, and the view isn't available on watchOS.

## Topics

### Decoding

- ``Nuke/ImageDecoders/Video``
- ``Nuke/ImageContainer/UserInfoKey/videoAssetKey``
- ``Nuke/AssetType/isVideo``

### Playback

- ``VideoPlayerView``
