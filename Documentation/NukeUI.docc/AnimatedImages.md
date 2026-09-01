# Animated Images

Play GIF, APNG, animated WebP, and animated HEIC.

## Overview

An animated image arrives as a container the pipeline recognizes as animated: the still it decoded, the encoded bytes (``ImageContainer/data``), and the animation it parsed out of them (``ImageContainer/animation``). NukeUI turns that into playback – it decodes the frames off the main thread, keeps a bounded number of them in memory, and shows each one when the file says it should.

Nothing needs to be enabled. ``LazyImage`` and ``LazyImageView`` play animations by default:

```swift
LazyImage(url: URL(string: "https://example.com/cat.gif"))
```

The formats are whatever Image I/O can read and the decoder recognizes as animated: GIF, APNG, animated WebP, and HEIC and AVIF sequences. There is no per-format code – ``Nuke/AnimatedImageSource`` reads the frame count, the delays, and the loop count from the container, and the rest is the same for all of them.

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

``LazyImageState/animatedImage`` is `nil` for everything that isn't animated, which is the signal to display the still image. Like `Image`, ``AnimatedImage`` displays at its natural size until you call ``AnimatedImage/resizable(contentMode:)``, and it lays out the way an `Image` does after that: `.fit` takes the size the frames occupy, `.fill` covers what it is offered and clips the rest.

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

A plain `UIImageView` shows the still frame instead.

On macOS, `NSImageView.imageScaling` only ever fits the image inside the view. `AnimatedImageView.isAspectFillEnabled` is the missing aspect-fill mode – the view draws the frames itself while it is on – and it is what ``AnimatedImage/resizable(contentMode:)`` uses for `.fill`.

The view plays only while it is in a window, so an animation in a cell that scrolls out of sight stops decoding frames and picks up where it left off when it comes back. Call ``AnimatedImageView/prepareForReuse()`` from your cell's `prepareForReuse()`.

## How Playback Works

``Nuke/AnimatedImageSource`` parses the container: the frame count, the delay of each frame, the loop count, and the canvas size. It decodes nothing, and it is `nil` for anything that isn't animated, including a single-frame GIF. The pipeline parses it while it decodes the image – on the decoding queue, once, with the result cached alongside the image – so a view is handed an animation rather than data to find one in. Set ``Nuke/ImagePipeline/Configuration-swift.struct/isAnimatedImageParsingEnabled`` to `false` to skip it in an app that plays animations some other way.

``AnimatedImagePlayer`` owns the frame buffer and the clock. It decodes frames on a background actor, one at a time, in playback order, and hands the current one to a view. ``AnimatedImageView`` and ``AnimatedImage`` both create a player of their own unless you hand them one.

### Timing

Playback follows the wall clock rather than the decoder. Every tick of the display link adds the elapsed time to a budget, and the player advances through as many frames as the budget covers. An animation that takes three seconds on paper takes three seconds on screen, even if the main thread stalls or the decoder falls behind; what gives is the number of frames actually shown. The one exception is an animation whose frames take longer to decode than they are shown for: skipping the late frames there would mean skipping all of them, so the player shows the late frame and moves the playhead back to it, and the animation plays slow rather than stopping.

Two corrections are applied to the delays the file declares, and both are what browsers do: a missing or non-positive delay becomes 0.1 s, and so does a delay below 0.011 s, which was written by a tool that meant "as fast as you can".

The clock runs no faster than the animation needs: a 10 fps GIF asks for a 20 Hz display link rather than the 60 or 120 Hz the display is capable of. Every animation is driven by one display link for the process, which runs while any animation is playing at the rate the fastest of them asks for.

### The Frame Buffer

Decoding every frame up front is the fastest way to run out of memory: a 1000×1000 animation with 60 frames is 240 MB of bitmaps. The player keeps a window of frames instead, starting at the one on screen, and refills it in playback order as the window moves.

The window is sized by a memory budget – ``AnimatedImagePlayer/Options/maxBufferSize``, 10 MB by default – rather than a frame count, because 60 thumbnails and 60 full-screen frames are two orders of magnitude apart in memory. That budget is a ceiling rather than an allowance: what the player actually gets is its share of ``AnimatedImageFramePool``, described below.

That gives two regimes:

- **The animation fits.** The window covers every frame, nothing is ever evicted, and each frame is decoded exactly once. This is the common case for the small animations that appear in lists.
- **The animation doesn't fit.** The window slides, and the frames behind it are dropped and decoded again on the next loop. Playback is smooth; the cost is a decode per frame for as long as it plays.

Each frame is decoded and then drawn into a bitmap the player owns, which moves the decompression that would otherwise happen on the main thread onto a background actor, and produces a bitmap in the layout the compositor wants.

A player that has not started playing – or one that has stopped because nobody is watching – decodes the first frame so that there is something to show, holds two frames at most, and fills the rest of the window when ``AnimatedImagePlayer/play()`` is called. A list of animations that are all showing their first frame costs a couple of bitmaps each rather than a full budget each.

## Memory

Every animation on screen draws its frames from one budget. A player asks ``AnimatedImageFramePool`` for enough memory to hold its animation – no more than its own ``AnimatedImagePlayer/Options/maxBufferSize`` – and the pool answers with a share of ``AnimatedImageFramePool/costLimit``. Nothing is divided while the animations together want less than the limit, and the division is even past that, except that an animation that fits in less than its share takes only what it needs and leaves the rest to the ones that can use it.

The limit is 5% of the device's physical memory by default, capped at 128 MB:

```swift
AnimatedImageFramePool.shared.costLimit = 32 * 1_048_576
```

One thing sits outside it: a player always holds two frames, because with one the next frame could only start decoding after the current one was dropped. A hundred animations at once will exceed any limit.

Three levers, in the order you should reach for them.

**Downsample large animations.** ``AnimatedImagePlayer/Options/maxPixelSize`` scales the frames as they are decoded, which cuts what each one costs by the square of the scale. An animation displayed in a 120-point cell does not need 1000-pixel frames: at 3× that is 0.5 MB a frame instead of 4 MB.

``AnimatedImageView`` does it for you – it decodes the frames no larger than it displays them, and never scales them up. How large that is depends on the content mode: covering the view is done with the frames' shorter side, so a 400×100 animation filling a 100×100 view needs 400-pixel frames. A content mode that draws the frames at their own size, like `.center`, turns the downsampling off.

Set the size yourself when the view isn't the whole story, or turn it off with ``AnimatedImageView/isAutomaticDownsamplingEnabled`` when the view is going to grow:

```swift
var options = AnimatedImagePlayer.Options()
options.maxPixelSize = 240
imageView.playerOptions = options
```

**Size the buffer.** Raising ``AnimatedImagePlayer/Options/maxBufferSize`` trades memory for CPU: past the point where the whole animation fits, each frame is decoded once and never again. The buffer never holds fewer than two frames.

**Let it respond to pressure.** A player shrinks its buffer to the minimum on a memory warning, and refills as playback continues. The window it was sized for comes back a minute later, or sooner if the app is backgrounded and returns. ``AnimatedImagePlayer/reduceMemoryUsage()`` shrinks it on demand.

A player nobody is watching gives its window back too. ``AnimatedImageView`` sets ``AnimatedImagePlayer/keepsFullBuffer`` to `false` when it pauses because it left its window, so the animations a list has scrolled past cost two frames each rather than a budget each. Playback paused in place keeps its frames, so that resuming doesn't stall.

Memory is bounded either way, but a screen full of animations that is over the pool's limit pays for it in decoding: every window is a share, the smaller windows slide, and the frames behind them are decoded again on every loop. Downsampling is the first lever because it is the one that makes the frames small enough for the shares to hold whole animations. Every frame except the one the animation is waiting on is decoded at `.utility`, so a grid of animations reading ahead queues behind the app's own work rather than beside it.

### Sharing

Every player showing one animation at one size draws from a single set of decoded frames, produced by a single decoder, so twenty copies of a sticker cost one sticker, and the nineteenth view to appear decodes nothing at all.

A player also falls in behind whatever is already playing, so the copies of an animation on a screen sit on the same frame and one window covers all of them. Turn it off with ``AnimatedImagePlayer/Options/isSynchronizationEnabled`` for a player that should always start at the beginning. The playheads only matter while the animation has to be windowed at all; when they scatter across an animation too large to hold, the players split what the animation was given.

Two views of the same animation at *different* sizes are two sets of frames. ``AnimatedImageView`` rounds the size it decodes for up to a step so that cells a fraction of a point apart still share.

The frames outlive the players holding them: a cell that scrolls off screen and comes back finds them still in memory. They are given back when the pool needs the room, and go for good when the animation itself does – they last exactly as long as something, usually ``ImageCache``, still holds the ``AnimatedImageSource`` they came from.

``AnimatedImagePlayer/Diagnostics/sharingPlayerCount`` reports how many players are drawing from the same frames, and ``AnimatedImageFramePool/animationCount`` how many distinct sets of frames the pool is holding.

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

The player is an `ObservableObject`, so a SwiftUI control of your own can read its state and be redrawn when it changes:

```swift
@ObservedObject var player: AnimatedImagePlayer

Button(player.isPlaying ? "Pause" : "Play") {
    player.isPlaying ? player.pause() : player.play()
}
```

What is published is the playback state changing – it starts, stops, finishes its loops, or something moves the playhead – and deliberately not the animation running: a SwiftUI graph invalidated 20 times a second to redraw a picture the view has already drawn is the cost this design exists to avoid. ``AnimatedImagePlayer/currentFrameIndex`` and ``AnimatedImagePlayer/completedLoopCount`` advance without a signal; sample ``AnimatedImagePlayer/diagnostics`` on a timer when you want to watch them move.

``AnimatedImagePlayer/onFrame`` stays yours as well: the views take the frames of a player they are given through a channel of their own, so a player already driving a scrubber of yours goes on driving it.

``AnimatedImagePlayer/Options`` covers the rest: ``AnimatedImagePlayer/Options/playbackRate`` for speed, and ``AnimatedImagePlayer/Options/repeatCount`` for how many times to play. The default, ``AnimatedImagePlayer/RepeatCount/image``, honors what the file asks for, which for the vast majority of animations is "forever"; ``AnimatedImagePlayer/RepeatCount/finite(_:)`` stops on the last frame and calls ``AnimatedImagePlayer/onFinish``.

To show an animation as a still – a list where animations play only after the user asks for them – set ``AnimatedImageView/isPlaybackEnabled`` to `false`. The first frame is displayed and no frames beyond it are ever decoded.

That is also where Accessibility › Motion › Auto-Play Animated Images lands. ``AnimatedImage`` reads it from the SwiftUI environment and holds the animation on its first frame while the setting is off. A player you own still plays when something asks it to, so a play button of your own keeps working. UIKit and AppKit publish no equivalent, so an ``AnimatedImageView`` used outside SwiftUI has to be told.

## Diagnostics

``AnimatedImagePlayer/diagnostics`` is a snapshot of what the player and its buffer are doing:

- **Is the animation fully buffered?** ``AnimatedImagePlayer/Diagnostics/isFullyBuffered``, along with ``AnimatedImagePlayer/Diagnostics/bufferedFrameCount`` and ``AnimatedImagePlayer/Diagnostics/bufferedByteCount``, says whether the whole thing is in memory or the window is sliding.
- **What does a frame cost?** ``AnimatedImagePlayer/Diagnostics/averageDecodeDuration`` and ``AnimatedImagePlayer/Diagnostics/maxDecodeDuration``. ``AnimatedImagePlayer/Diagnostics/decodedFrameCount`` climbing past the frame count is the buffer re-decoding frames it had to evict.
- **Is playback keeping up?** ``AnimatedImagePlayer/Diagnostics/effectiveFrameRate`` against ``Nuke/AnimatedImageSource/nominalFrameRate``. ``AnimatedImagePlayer/Diagnostics/skippedFrameCount`` counts the frames the player was too far behind to show, and ``AnimatedImagePlayer/Diagnostics/bufferMissCount`` the ones that were due before they finished decoding.

The **Animated Images** screen in the demo app puts all of it on screen, with a map of the buffer, over a real animation.

## What Isn't Animated

Two cases where an animation deliberately becomes a still:

- **A processed image.** A processor produces a new image, and the encoded animation no longer describes it, so the pipeline drops the data and the animation with it. A processor that implements ``ImageProcessing/process(_:context:)`` decides for itself and can keep both – one that processes the frames, say.
- **A thumbnail request.** ``ImageRequest/thumbnail`` exists to avoid decoding the image at full size, and playing the full-size animation would undo that. Neither the data nor the animation is attached.

Also worth knowing: GIF is not an efficient format for what it is usually asked to do. A short, silent, looping MP4 is a fraction of the size and is decoded by dedicated hardware. `NukeVideo` plays those.

## Topics

### Views

- ``AnimatedImage``
- ``AnimatedImageView``

### Playback

- ``AnimatedImagePlayer``
- ``Nuke/AnimatedImageSource``

### Memory

- ``AnimatedImageFramePool``
