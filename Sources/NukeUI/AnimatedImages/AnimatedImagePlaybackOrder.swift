// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

/// The order a player shows the frames of an animation in.
///
/// A playhead moves through positions, one for every frame it shows, and the
/// order says which frame is at each of them. In a forward animation the two
/// are the same number. They can't be in general because of a bounce, which
/// shows every frame between the ends twice a loop: a frame alone doesn't say
/// which way the playhead is heading.
struct AnimatedImagePlaybackOrder {
    let mode: AnimatedImagePlayer.PlaybackMode
    let frameCount: Int

    /// The number of positions in one loop: one per frame, or for a bounce the
    /// way there and the way back, which show the frame at each end once.
    let loopLength: Int

    init(mode: AnimatedImagePlayer.PlaybackMode, frameCount: Int) {
        self.mode = mode
        self.frameCount = frameCount
        self.loopLength = mode == .bounce ? 2 * frameCount - 2 : frameCount
    }

    /// Returns the frame at the given position, which may run past the end of
    /// the loop and wrap around.
    func frameIndex(at position: Int) -> Int {
        switch mode {
        case .forward:
            return position % frameCount
        case .reverse:
            return frameCount - 1 - position % frameCount
        case .bounce:
            let position = position % loopLength
            return position < frameCount ? position : loopLength - position
        }
    }

    /// Returns `true` if the given number of positions from `position` onward
    /// show the frame at the given index.
    func covers(_ index: Int, from position: Int, length: Int) -> Bool {
        switch mode {
        case .forward:
            return (index - position + frameCount) % frameCount < length
        case .reverse:
            return (frameCount - 1 - index - position + frameCount) % frameCount < length
        case .bounce:
            // A window of every frame is the whole animation, wherever it
            // starts, although that many positions from one that is heading
            // back don't reach all of them.
            guard length < frameCount else { return true }
            let position = position % loopLength
            let there = (index - position + loopLength) % loopLength
            let back = (2 * loopLength - index - position) % loopLength
            return min(there, back) < length
        }
    }

    /// Returns the position of the frame at the given index for a playhead
    /// moving there from `position`.
    func position(of index: Int, from position: Int) -> Int {
        switch mode {
        case .forward:
            return index
        case .reverse:
            return frameCount - 1 - index
        case .bounce:
            // Between the ends a frame has two positions. The one on the way
            // the playhead is already heading keeps it heading there.
            let isHeadingBack = position >= frameCount
            return isHeadingBack && index > 0 && index < frameCount - 1 ? loopLength - index : index
        }
    }
}
