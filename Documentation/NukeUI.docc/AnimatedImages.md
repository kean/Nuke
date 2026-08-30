# Animated Images

Play GIF, APNG, animated WebP, and animated HEIC.

## Overview

An animated image arrives as a container the pipeline recognizes as animated: the still it decoded, plus the encoded bytes it came from (``ImageContainer/data``). NukeUI turns that into playback – it decodes the frames off the main thread, keeps a bounded number of them in memory, and shows each one when the file says it should.

Nothing needs to be enabled. ``LazyImage`` and ``LazyImageView`` play animations by default:

```swift
LazyImage(url: URL(string: "https://example.com/cat.gif"))
```

The formats are whatever Image I/O can read and Nuke can recognize as animated: GIF, APNG, animated WebP, and animated HEIC and AVIF sequences. There is no per-format code – ``AnimatedImageSource`` reads the frame count, the delays, and the loop count from the container, and the rest of the pipeline is the same for all of them.

## Displaying Animations

### SwiftUI

The default ``LazyImage`` content plays animations. When you write your own content closure, ``LazyImageState/animatedImage`` is the animation and ``AnimatedImage`` is the view that plays it:

```swift
LazyImage(url: url) { state in
    if let animatedImage = state.animatedImage {
        AnimatedImage(animatedImage).resizable().scaledToFill()
    } else if let image = state.image {
        image.resizable().scaledToFill()
    } else {
        Color.secondary.opacity(0.2)
    }
}
```

``LazyImageState/animatedImage`` is `nil` for everything that isn't animated, which is the signal to display the still image. Like `Image`, ``AnimatedImage`` displays at its natural size until you call ``AnimatedImage/resizable(contentMode:)``.

### UIKit and AppKit

``LazyImageView`` plays animations through its ``LazyImageView/imageView``, which is an ``AnimatedImageView``:

```swift
let imageView = LazyImageView()
imageView.url = url
```

``AnimatedImageView`` is a `UIImageView` (an `NSImageView` on macOS) that plays animated images, so it also works with the image view extensions and anywhere else a platform image view does:

```swift
let imageView = AnimatedImageView()
imageView.contentMode = .scaleAspectFill
NukeUI.loadImage(with: url, into: imageView)
```

A plain `UIImageView` shows the still frame instead; playing an animation is the one thing it can't do.

The view plays only while it is in a window, so an animation in a cell that scrolls out of sight stops decoding frames and picks up where it left off when it comes back. Call ``AnimatedImageView/prepareForReuse()`` from your cell's `prepareForReuse()`.

## How Playback Works

Three pieces, one per concern.

``AnimatedImageSource`` parses the container: the frame count, the delay of each frame, the loop count, and the canvas size. It decodes nothing – Image I/O answers all of that from the container – and it returns `nil` for anything that isn't animated, including a single-frame GIF.

``AnimatedImagePlayer`` owns the frame buffer and the clock. It decodes frames on a background actor, one at a time, in playback order, and hands the current one to a view.

The view displays what it is given. ``AnimatedImageView`` and ``AnimatedImage`` both create a player of their own unless you hand them one.

### Timing

Playback follows the wall clock rather than the decoder. Every tick of the display link adds the elapsed time to a budget, and the player advances through as many frames as the budget covers. An animation that takes three seconds on paper takes three seconds on screen, even if the main thread stalls or the decoder falls behind; what gives is the number of frames actually shown, not the duration. It is the same trade-off a video player makes, and it is the reason two animations started together stay in step.

There is one animation the wall clock can't be held for: one whose frames take longer to decode than they are shown for, which is what a very large animation in a sliding window comes to. Every frame there arrives after the playhead has passed it, so skipping the late ones would mean skipping all of them. The player shows the frame and moves the playhead back to it instead, and the animation plays slow rather than stopping.

Two corrections are applied to the delays the file declares, and both are what browsers do:

- A missing or non-positive delay becomes 0.1 s.
- A delay below 0.011 s becomes 0.1 s. A file asking for 100 fps was written by a tool that meant "as fast as you can", and honoring it literally burns CPU to produce a flicker.

The clock runs no faster than the animation needs. A 10 fps GIF asks for a 20 Hz display link rather than the 60 or 120 Hz the display is capable of, which is a measurable power win in a list full of animations.

### The Frame Buffer

Decoding every frame up front is the fastest way to play an animation and the fastest way to run out of memory: a 1000×1000 animation with 60 frames is 240 MB of bitmaps. The player keeps a window of frames instead, starting at the one on screen, and refills it in playback order as the window moves.

The window is sized by a memory budget – ``AnimatedImagePlayer/Options/maxBufferSize``, 10 MB by default – rather than a frame count, because that is what actually matters: 60 thumbnails and 60 full-screen frames are the same number of frames and two orders of magnitude apart in memory.

That gives two regimes:

- **The animation fits.** The window covers every frame, nothing is ever evicted, and each frame is decoded exactly once no matter how long the animation plays. This is the common case for the small animations that appear in lists.
- **The animation doesn't fit.** The window slides, and the frames behind it are dropped and decoded again on the next loop. Playback is smooth; the cost is a decode per frame for as long as it plays.

Each frame is decoded and then drawn into a bitmap the player owns, which moves the decompression that would otherwise happen on the main thread – during a frame, while scrolling – onto a background actor, and produces a bitmap in the layout the compositor wants.

A player that has not started playing is a third regime: it decodes the first frame so that there is something to show, holds two frames at most, and fills the rest of the window when ``AnimatedImagePlayer/play()`` is called. A list of animations that are all showing their first frame – ``AnimatedImageView/isPlaybackEnabled`` set to `false`, say – costs a couple of bitmaps each rather than a full budget each.

## Memory

Three things to reach for, in the order you should reach for them.

**Downsample large animations.** ``AnimatedImagePlayer/Options/maxPixelSize`` scales the frames as they are decoded, which cuts what each one costs by the square of the scale. An animation displayed in a 120-point cell does not need 1000-pixel frames:

```swift
var options = AnimatedImagePlayer.Options()
options.maxPixelSize = 240
imageView.playerOptions = options
```

**Size the buffer.** Raising ``AnimatedImagePlayer/Options/maxBufferSize`` trades memory for CPU – past the point where the whole animation fits, each frame is decoded once and never again. Lowering it does the opposite. The buffer never holds fewer than two frames: with one, the next frame could only start decoding after the current one was dropped, and playback would stall on every frame.

**Let it respond to pressure.** A player shrinks its buffer to the minimum on a memory warning, and refills as playback continues. ``AnimatedImagePlayer/reduceMemoryUsage()`` does the same thing on demand.

## Controlling Playback

Create the player yourself when you want to control it – or read its diagnostics:

```swift
let player = AnimatedImagePlayer(source: source)
player.play()
```

Both views take one:

```swift
imageView.player = player      // UIKit and AppKit
AnimatedImage(player: player)  // SwiftUI
```

The player exposes ``AnimatedImagePlayer/play()``, ``AnimatedImagePlayer/pause()``, ``AnimatedImagePlayer/restart()``, and ``AnimatedImagePlayer/seek(toFrame:)``, and reports what it is doing through ``AnimatedImagePlayer/currentFrameIndex``, ``AnimatedImagePlayer/completedLoopCount``, ``AnimatedImagePlayer/isPlaying``, and ``AnimatedImagePlayer/isFinished``.

``AnimatedImagePlayer/Options`` covers the rest: ``AnimatedImagePlayer/Options/playbackRate`` for speed, and ``AnimatedImagePlayer/Options/repeatCount`` for how many times to play. The default, ``AnimatedImagePlayer/RepeatCount/image``, honors what the file asks for, which for the vast majority of animations is "forever"; ``AnimatedImagePlayer/RepeatCount/finite(_:)`` stops on the last frame and calls ``AnimatedImagePlayer/onFinish``.

To show an animation as a still – a list where animations play only after the user asks for them – set ``AnimatedImageView/isPlaybackEnabled`` to `false`. The first frame is displayed and no frames beyond it are ever decoded.

## Diagnostics

``AnimatedImagePlayer/diagnostics`` is a snapshot of what the player and its buffer are doing. It answers the questions that are otherwise guesswork:

- **Is the animation fully buffered?** ``AnimatedImagePlayer/Diagnostics/isFullyBuffered``, along with ``AnimatedImagePlayer/Diagnostics/bufferedFrameCount`` and ``AnimatedImagePlayer/Diagnostics/bufferedByteCount``, says whether the whole thing is in memory or the window is sliding.
- **What does a frame cost?** ``AnimatedImagePlayer/Diagnostics/averageDecodeDuration`` and ``AnimatedImagePlayer/Diagnostics/maxDecodeDuration``. ``AnimatedImagePlayer/Diagnostics/decodedFrameCount`` climbing past the frame count is the buffer re-decoding frames it had to evict.
- **Is playback keeping up?** ``AnimatedImagePlayer/Diagnostics/effectiveFrameRate`` against ``AnimatedImageSource/nominalFrameRate``. A gap means frames are being passed over: ``AnimatedImagePlayer/Diagnostics/skippedFrameCount`` counts the ones the player was too far behind to show, and ``AnimatedImagePlayer/Diagnostics/bufferMissCount`` the ones that were due before they finished decoding.

The **Animated Images** screen in the demo app puts all of it on screen, with a map of the buffer, over a real animation.

## What Isn't Animated

Two cases where an animation deliberately becomes a still, both because the alternative is worse:

- **A processed image.** A processor produces a new image, and the encoded animation no longer describes it, so the pipeline drops the data. Otherwise you would see the original animation playing over a processed still.
- **A thumbnail request.** ``ImageRequest/thumbnail`` exists to avoid decoding the image at full size; the data is the full-size animation, and playing it would undo that.

Also worth knowing: GIF is not an efficient format for what it is usually asked to do. A short, silent, looping MP4 is a fraction of the size and is decoded by dedicated hardware. `NukeVideo` plays those.

## Topics

### Views

- ``AnimatedImage``
- ``AnimatedImageView``

### Playback

- ``AnimatedImagePlayer``
- ``AnimatedImageSource``
