# Animated Images

Play GIF, APNG, animated WebP, and HEIC and AVIF sequences.

## Overview

An animated image arrives as a container the pipeline recognizes as animated: the still it decoded, the encoded bytes (``ImageContainer/data``), and the animation it parsed out of them (``ImageContainer/animation``). NukeUI turns that into playback – it decodes the frames off the main thread, keeps a bounded number of them in memory, and shows each one when the file says it should.

Nothing needs to be enabled. ``LazyImage`` and ``LazyImageView`` play animations by default:

```swift
LazyImage(url: URL(string: "https://example.com/cat.gif"))
```

The formats are whatever Image I/O can read and the decoder recognizes as animated: GIF, APNG, animated WebP, and HEIC and AVIF sequences. There is no per-format code – ``Nuke/AnimatedImageSource`` reads the frame count, the delays, and the loop count from the container, and the rest is the same for all of them.

## Displaying Animations

### SwiftUI

The default ``LazyImage`` content plays animations. When you write your own content closure, ``AnimatedImage`` is the view that plays them:

```swift
LazyImage(url: url) { state in
    if let container = state.imageContainer, let animation = AnimatedImage(container: container) {
        animation.resizable().scaledToFill()
    } else if let image = state.image {
        image.resizable().scaledToFill()
    } else {
        Color.secondary.opacity(0.2)
    }
}
```

``AnimatedImage/init(container:)`` returns `nil` for everything that isn't animated, which is the signal to display the still image. It also carries the still the decoder produced, which holds the place until the first frame is decoded – without one the view is blank every time an animation appears. ``LazyImageState/animatedImage`` is the animation on its own, for a view you build yourself.

Like `Image`, ``AnimatedImage`` displays at its natural size until you call ``AnimatedImage/resizable()``, and it lays out the way an `Image` does after that – `scaledToFit()`, `scaledToFill()`, `frame(width:height:)`, and the rest.

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

The view plays only while it is in a window, so an animation in a cell that scrolls out of sight stops decoding frames and picks up where it left off when it comes back. Call ``AnimatedImageView/prepareForReuse()`` from your cell's `prepareForReuse()`.

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

``AnimatedImagePlayer/Options`` covers the rest: ``AnimatedImagePlayer/Options/playbackRate`` for speed, and ``AnimatedImagePlayer/Options/repeatCount`` for how many times to play. The default, ``AnimatedImagePlayer/RepeatCount/image``, honors what the file asks for, which for the vast majority of animations is "forever" – a GIF carrying no Netscape loop extension asks to be played once, and is, the way a browser plays it. ``AnimatedImagePlayer/RepeatCount/finite(_:)`` stops on the last frame and calls ``AnimatedImagePlayer/onFinish``.

To show an animation as a still – a list where animations play only after the user asks for them – set ``AnimatedImageView/isPlaybackEnabled`` to `false`. The first frame is displayed and no frames beyond it are ever decoded.

That is also where Accessibility › Motion › Auto-Play Animated Images lands. ``AnimatedImage`` reads it from the SwiftUI environment and holds the animation on its first frame while the setting is off. A player you own still plays when something asks it to, so a play button of your own keeps working. UIKit and AppKit publish no equivalent, so an ``AnimatedImageView`` used outside SwiftUI has to be told.

## Memory

Decoding every frame up front is the fastest way to run out of memory: a 1000×1000 animation with 60 frames is 240 MB of bitmaps. So there are two ways an animation is played. One that fits in memory is decoded exactly once and kept. One that doesn't is played out of a window: the player holds the frame on screen and the two after it, decoding each frame again as the animation comes back round to it – and asks for nothing more, because a window that slides re-decodes every frame each loop however long it is, and memory past what absorbs a slow decode is better left to the animations that fit.

Which of the two it is falls to ``AnimatedImageFramePool``, which every animation on screen draws its frames from. Its ``AnimatedImageFramePool/costLimit`` is 5% of the device's physical memory, capped at 128 MB, and an animation alone may take all of it:

```swift
AnimatedImageFramePool.shared.costLimit = 32 * 1_048_576
```

What is measured is what the frames cost decoded – the canvas at four bytes a pixel, less whatever downsampling scales away – never the size of the file, which says nothing about it: a 500×280 GIF of 22 frames is 400 KB on disk and 12 MB decoded.

When the animations together want more than the limit, the pool gives each one its window first and holds as many of them whole as the rest allows, smallest first – so a wall of stickers and one long GIF keeps every sticker whole and plays the GIF out of a window, where an even split would hold nothing whole. When two the same size compete for the last of it, the one already whole keeps its frames. One thing sits outside the limit: a player always holds two frames, because with one the next frame could only start decoding after the current one was dropped. A hundred animations at once will exceed any limit.

Two levers, in the order you should reach for them.

**Downsample large animations.** ``AnimatedImagePlayer/Options/maxPixelSize`` scales the frames as they are decoded, which cuts what each one costs by the square of the scale. An animation displayed in a 120-point cell does not need 1000-pixel frames: at 3× that is 0.5 MB a frame instead of 4 MB. It is the first lever because it is the one that makes the frames small enough for the pool to hold whole animations.

``AnimatedImageView`` does it for you – it decodes the frames no larger than it displays them, and never scales them up. Set the size yourself when the view isn't the whole story, or turn it off with ``AnimatedImageView/isAutomaticDownsamplingEnabled`` when the view is going to grow:

```swift
var options = AnimatedImagePlayer.Options()
options.maxPixelSize = 240
imageView.playerOptions = options
```

**Raise the limit.** ``AnimatedImageFramePool/costLimit`` decides how many animations fit, and trades memory for CPU: one that fits is decoded once and never again, one that doesn't is decoded for as long as it plays. ``AnimatedImagePlayer/Options/maxBufferSize`` goes the other way: it is a ceiling on one player, for an animation that should play out of a window however much room the pool has.

Memory is bounded either way. On a memory warning the pool holds every animation at two frames and gives the windows back a minute later, or sooner if the app is backgrounded and returns; ``AnimatedImageFramePool/reduceMemoryUsage()`` does the same on demand. A player nobody is watching gives its window back too, so the animations a list has scrolled past cost almost nothing.

### Sharing

Every player showing one animation at one size draws from a single set of decoded frames, produced by a single decoder, so twenty copies of a sticker cost one sticker, and the nineteenth view to appear decodes nothing at all. A player also falls in behind whatever is already playing, so the copies on a screen sit on the same frame and one window covers all of them – turn that off with ``AnimatedImagePlayer/Options/isSynchronizationEnabled`` for a player that should always start at the beginning.

Two views of the same animation at *different* sizes are two sets of frames, though ``AnimatedImageView`` rounds the size it decodes for up to a step so that cells a fraction of a point apart still share.

The frames outlive the players holding them: a cell that scrolls off screen and comes back finds them still in memory. They are given back when the pool needs the room, and go for good when the animation itself does – they last exactly as long as something, usually ``ImageCache``, still holds the ``AnimatedImageSource`` they came from.

## Diagnostics

``AnimatedImagePlayer/diagnostics`` is a snapshot of what the player is doing:

- **Is the animation fully buffered?** ``AnimatedImagePlayer/Diagnostics/isFullyBuffered``, along with ``AnimatedImagePlayer/Diagnostics/bufferedFrameCount`` and ``AnimatedImagePlayer/Diagnostics/bufferedByteCount``, says whether the whole thing is in memory or the window is sliding.
- **What does a frame cost?** ``AnimatedImagePlayer/Diagnostics/averageDecodeDuration`` and ``AnimatedImagePlayer/Diagnostics/maxDecodeDuration``. ``AnimatedImagePlayer/Diagnostics/decodedFrameCount`` climbing past the frame count means frames are being evicted and decoded again.
- **Is playback keeping up?** ``AnimatedImagePlayer/Diagnostics/effectiveFrameRate`` against ``Nuke/AnimatedImageSource/nominalFrameRate``, and ``AnimatedImagePlayer/Diagnostics/bufferMissCount``, which counts the frames that were due before they finished decoding – each one held the frame before it on screen past its delay.
- **How much is shared?** ``AnimatedImagePlayer/Diagnostics/sharingPlayerCount`` reports how many players are drawing from the same frames, and ``AnimatedImageFramePool/animationCount`` how many distinct sets of frames the pool is holding.

The **Animated Images** screen in the demo app puts all of it on screen, with a map of the window, over a real animation.

## Custom Frames

Two hooks for the frames themselves, both of them on the decoder rather than the main actor.

**Transform every frame.** ``AnimatedImagePlayer/Options/frameTransform`` runs as each frame is decoded – a tint, a rounded corner, a filter – and the animation goes on playing, which is what a processor can't do:

```swift
var options = AnimatedImagePlayer.Options()
options.frameTransform = AnimatedImageFrameTransform(identifier: "grayscale") {
    $0.copy(colorSpace: CGColorSpaceCreateDeviceGray())
}
imageView.playerOptions = options
```

The identifier is what the frames are shared by: players that ask for the same one draw from a single set of transformed frames, players that ask for different ones each get a set of their own. The transform runs once per decoded frame, which for an animation too large to hold in memory is once per frame per loop, so it is worth keeping to what a frame's worth of time affords.

**Produce the frames yourself.** ``AnimatedImageFrameDecoding`` is where every frame comes from – ``AnimatedImageFrameDecoder``, which draws them with Image I/O, is the one that ships – and ``AnimatedImageFrameDecoderRegistry`` is where an implementation of your own goes:

```swift
AnimatedImageFrameDecoderRegistry.shared.register { context in
    guard AssetType(context.source.data) == .webp else { return nil } // Pass
    return WebPFrameDecoder(source: context.source, maxPixelSize: context.maxPixelSize)
}
```

The decoder is picked once per animation and size, when the first player asks for its frames, so register at startup. Everything else is unchanged: the frames it produces are windowed, shared, and counted against the pool exactly as Image I/O's are, and it is asked for one frame at a time.

The container is still parsed by Image I/O, though. ``Nuke/AnimatedImageSource`` is what says how many frames there are and how long each one is shown, and there is no animation to play at all for data Image I/O can't read – so a decoder of your own answers "what does frame *n* look like", not "what is in this file".

## What Isn't Animated

Two cases where an animation deliberately becomes a still:

- **A processed image.** A processor produces a new image, and the encoded animation no longer describes it, so the pipeline drops the data and the animation with it. A processor that implements ``ImageProcessing/process(_:context:)`` decides for itself and can keep both – one that processes the frames, say. To change the frames of an animation that goes on playing, reach for ``AnimatedImagePlayer/Options/frameTransform`` instead.
- **A thumbnail request.** ``ImageRequest/thumbnail`` exists to avoid decoding the image at full size, and playing the full-size animation would undo that. Neither the data nor the animation is attached.

Also worth knowing: GIF is not an efficient format for what it is usually asked to do. A short, silent, looping MP4 is a fraction of the size and is decoded by dedicated hardware. `NukeVideo` plays those.

## Under the Hood

``Nuke/AnimatedImageSource`` parses the container – the frame count, the delays, the loop count, the canvas size – and decodes nothing. The pipeline parses it while it decodes the image, on the decoding queue, once, with the result cached alongside the image, so a view is handed an animation rather than data to find one in. Set ``Nuke/ImagePipeline/Configuration-swift.struct/isAnimatedImageParsingEnabled`` to `false` to skip it in an app that plays animations some other way.

Playback never skips a frame. Each one is shown for at least its delay, and the next one appears when that delay is up and the frame is decoded, whichever comes later – so under load the animation stretches rather than jumps. A stall on the main thread or a frame that is slow to decode holds the frame on screen for longer, and the time lost isn't made up afterwards; what gives is how long the animation takes, not which of its frames are seen. This is what a browser does, and the trade is the right one for images: an animation that is never seen to jump, for one that can't be relied on to take three seconds when it says it does. The one thing passed over is a frame shorter than a tick of the clock, which the display couldn't have shown for longer anyway. Two corrections are applied to the delays the file declares, both of them what browsers do: a missing or non-positive delay becomes 0.1 s, and so does a delay below 0.011 s, which was written by a tool that meant "as fast as you can".

The frames are decoded at the priority of the screen. With two frames of read-ahead, every decode is one the display is about to wait for, and the decoder is paced by playback – one frame per frame shown – rather than by how much memory there is, which is what keeps a wall of animations from turning into CPU-bound work.

Each player is driven by a display link of its own, which runs while the player is playing and asks for no more than its animation needs – a 10 fps GIF asks for 20 Hz rather than the 120 the display is capable of. The system folds every link in the process into one wakeup per refresh, so a screen of them costs what one does.

## Topics

### Views

- ``AnimatedImage``
- ``AnimatedImageView``

### Playback

- ``AnimatedImagePlayer``
- ``Nuke/AnimatedImageSource``

### Frames

- ``AnimatedImageFrameTransform``
- ``AnimatedImageFrameDecoding``
- ``AnimatedImageFrame``
- ``AnimatedImageFrameDecoder``
- ``AnimatedImageFrameDecoderRegistry``
- ``AnimatedImageFrameDecodingContext``

### Memory

- ``AnimatedImageFramePool``
