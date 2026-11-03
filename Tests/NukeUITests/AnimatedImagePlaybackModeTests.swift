// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Testing
@testable import Nuke
@testable import NukeUI

/// The animations the modes are played against: two made of patches on the
/// frames before them, which is what makes going backward hard, and two that
/// aren't.
enum PlaybackFixture: CaseIterable, CustomTestStringConvertible {
    case gifWithDisposal, apngWithDisposal, webp, heics

    var testDescription: String {
        switch self {
        case .gifWithDisposal: "GIF with disposal"
        case .apngWithDisposal: "APNG with disposal"
        case .webp: "WebP"
        case .heics: "HEIC sequence"
        }
    }

    func makeSource() throws -> AnimatedImageSource {
        let data = switch self {
        case .gifWithDisposal: DeltaAnimation.gif()
        case .apngWithDisposal: DeltaAnimation.apng()
        case .webp: Test.data(name: "animated", extension: "webp")
        case .heics: try #require(Test.animatedHEICS(frameCount: 6))
        }
        return try #require(AnimatedImageSource(data: data))
    }
}

/// ``AnimatedImagePlayer/PlaybackMode``: the frames each mode shows, in what
/// order, for how long, and what that costs the decoder and the pool.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImagePlaybackModeTests: AnimatedImagePoolSuite {
    let pool = AnimatedImageFramePool()

    // MARK: Frame Order

    @Test(arguments: PlaybackFixture.allCases)
    func forwardPlaysTheFramesTheWayTheFileStoresThem(_ fixture: PlaybackFixture) async throws {
        let source = try fixture.makeSource()

        let shown = await shownFrames(of: source, mode: .forward, count: source.frameCount * 2 + 1)

        #expect(shown == (source.frameCount == 6
            ? [0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0]
            : [0, 1, 2, 3, 0, 1, 2, 3, 0]))
    }

    @Test(arguments: PlaybackFixture.allCases)
    func reversePlaysThemFromTheLastToTheFirst(_ fixture: PlaybackFixture) async throws {
        let source = try fixture.makeSource()

        let shown = await shownFrames(of: source, mode: .reverse, count: source.frameCount * 2 + 1)

        #expect(shown == (source.frameCount == 6
            ? [5, 4, 3, 2, 1, 0, 5, 4, 3, 2, 1, 0, 5]
            : [3, 2, 1, 0, 3, 2, 1, 0, 3]))
    }

    @Test(arguments: PlaybackFixture.allCases)
    func bounceTurnsAtTheEndsWithoutShowingThemTwice(_ fixture: PlaybackFixture) async throws {
        let source = try fixture.makeSource()

        let shown = await shownFrames(of: source, mode: .bounce, count: source.frameCount * 4 - 3)

        #expect(shown == (source.frameCount == 6
            ? [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0]
            : [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0]))
    }

    @Test func twoFramesBounceBetweenThemselves() async {
        let source = Test.animatedGIFSource(frameCount: 2)

        #expect(await shownFrames(of: source, mode: .bounce, count: 5) == [0, 1, 0, 1, 0])
        #expect(await shownFrames(of: source, mode: .reverse, count: 5) == [1, 0, 1, 0, 1])
    }

    @Test func aSingleFrameIsNothingToPlayInAnyMode() {
        // The modes never have to work out what a bounce of one frame is:
        // both ways of describing an animation turn it down.
        #expect(AnimatedImageSource(data: Test.staticPNG()) == nil)
        let single = AnimatedImageSource(data: Data(), delays: [0.1], size: CGSize(width: 8, height: 8)) { _ in
            SolidColorFrameDecoder(id: "single", color: .red)
        }
        #expect(single == nil)
    }

    // MARK: Pixels

    @Test(arguments: [PlaybackFixture.gifWithDisposal, .apngWithDisposal], [AnimatedImagePlayer.PlaybackMode.reverse, .bounce])
    func framesOutOfFileOrderAreComposedTheSame(_ fixture: PlaybackFixture, mode: AnimatedImagePlayer.PlaybackMode) async throws {
        // GIVEN a window of two frames, so that every frame is asked of Image
        // I/O on its own, from wherever it composed the last one
        let source = try fixture.makeSource()
        var options = AnimatedImagePlayer.Options.twoFrameBuffer
        options.playbackMode = mode
        let (player, clock) = makeIdlePlayer(source: source, options: options)
        player.play()

        // WHEN it plays two loops of whichever kind
        for _ in 0..<(2 * player.order.loopLength) {
            await player.waitUntilFull()

            // THEN each frame comes out as the frames before it make it
            let image = try #require(player.image?.cgImage)
            #expect(DeltaAnimation.mismatches(in: image, frameAt: player.currentFrameIndex) == [])
            step(player, clock)
        }
    }

    @Test(arguments: [AnimatedImagePlayer.PlaybackMode.forward, .reverse, .bounce], [2, 3])
    func aWindowOfAnyLengthComposesFramesThatRestoreTheCanvas(_ mode: AnimatedImagePlayer.PlaybackMode, windowLength: Int) async throws {
        // GIVEN frames that each put the canvas back when they are done, in a
        // window that reaches them out of order
        let source = try #require(AnimatedImageSource(data: DeltaAnimation.apng(frames: DeltaAnimation.restoringFrames)))
        let pool = AnimatedImageFramePool(costLimit: windowLength * source.bytesPerFrame)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = mode
        let (player, clock) = AnimatedImageTest.makePlayer(source: source, options: options, pool: pool)
        player.play()

        for _ in 0..<(2 * player.order.loopLength) {
            await player.waitUntilFull()
            let image = try #require(player.image?.cgImage)
            #expect(DeltaAnimation.mismatches(in: image, frameAt: player.currentFrameIndex, of: DeltaAnimation.composedRestoringFrames) == [])
            step(player, clock)
        }
    }

    @Test(arguments: PlaybackFixture.allCases)
    func everyModeShowsTheSamePixelsForAFrame(_ fixture: PlaybackFixture) async throws {
        // GIVEN what each frame looks like decoded front to back
        let source = try fixture.makeSource()
        let decoder = AnimatedImageFrameDecoder(source: source)
        var forward: [RGBABitmap] = []
        for index in 0..<source.frameCount {
            let frame = try #require(await decoder.decode(at: index))
            forward.append(try #require(RGBABitmap(cgImage: frame)))
        }

        for mode in [AnimatedImagePlayer.PlaybackMode.reverse, .bounce] {
            var options = AnimatedImagePlayer.Options.twoFrameBuffer
            options.playbackMode = mode
            options.isSynchronizationEnabled = false
            let (player, clock) = makeIdlePlayer(source: source, options: options, pool: AnimatedImageFramePool())
            player.play()

            for _ in 0..<player.order.loopLength {
                await player.waitUntilFull()
                let image = try #require(player.image)
                #expect(RGBABitmap(image: image) == forward[player.currentFrameIndex])
                step(player, clock)
            }
        }
    }

    @Test func aSeekCarriesOnOverTheRightCanvas() async throws {
        // A seek lands on the frame out of the blue in any mode, and what
        // comes after it is drawn over what the frame left behind.
        let source = try #require(AnimatedImageSource(data: DeltaAnimation.apng()))
        let (player, clock) = makeIdlePlayer(source: source, options: .twoFrameBuffer)
        player.play()
        await player.waitUntilFull()

        player.seek(toFrame: 4)
        await player.waitUntilFull()
        player.seek(toFrame: 2)
        await player.waitUntilFull()
        step(player, clock)
        await player.waitUntilFull()

        #expect(player.currentFrameIndex == 3)
        let image = try #require(player.image?.cgImage)
        #expect(DeltaAnimation.mismatches(in: image, frameAt: 3) == [])
    }

    // MARK: Delays

    @Test(arguments: [AnimatedImagePlayer.PlaybackMode.reverse, .bounce])
    func everyFrameIsShownForItsOwnDelay(_ mode: AnimatedImagePlayer.PlaybackMode) async {
        // GIVEN frames that each ask for a different delay
        let delays = [0.1, 0.2, 0.3, 0.4]
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = mode
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4, delays: delays, options: options, pool: pool)
        player.play()
        await player.waitUntilFull()

        // WHEN it plays a loop, a hundredth of a second at a time
        var shownFor: [(index: Int, ticks: Int)] = [(player.currentFrameIndex, 0)]
        for _ in 0..<(mode == .reverse ? 105 : 155) {
            clock.tick(0.01)
            if player.currentFrameIndex == shownFor.last?.index {
                shownFor[shownFor.count - 1].ticks += 1
            } else {
                shownFor.append((player.currentFrameIndex, 0))
            }
        }

        // THEN the frame on screen decides how long it stays, not its place
        // in the loop. The last one is still counting.
        for (index, ticks) in shownFor.dropLast() {
            #expect(abs(ticks - Int(delays[index] * 100)) <= 2, "frame \(index) stayed \(ticks) ticks")
        }
        #expect(shownFor.map(\.index).dropLast() == (mode == .reverse ? [3, 2, 1, 0] : [0, 1, 2, 3, 2, 1]))
    }

    // MARK: Loop Counts

    @Test func aReverseAnimationStopsOnItsFirstFrame() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        options.loopCount = .finite(2)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, options: options, pool: pool)
        var events: [String] = []
        player.onLoop = { events.append("loop \($0)") }
        player.onFinish = { events.append("finish") }
        player.play()
        await player.waitUntilFull()

        var shown = [player.currentFrameIndex]
        for _ in 0..<5 {
            clock.tick(0.1)
            shown.append(player.currentFrameIndex)
        }
        #expect(shown == [2, 1, 0, 2, 1, 0])
        #expect(!player.isFinished)

        // It is on screen for its whole delay, like the last frame of any
        // other animation.
        clock.tick(0.1)
        #expect(player.isFinished)
        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 2)
        #expect(events == ["loop 1", "loop 2", "finish"])
    }

    @Test func oneWayThereAndBackIsOneLoop() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .bounce
        options.loopCount = .finite(2)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 4, options: options, pool: pool)
        var events: [String] = []
        player.onLoop = { [unowned player] in events.append("loop \($0) on frame \(player.currentFrameIndex)") }
        player.onFinish = { [unowned player] in events.append("finish on frame \(player.currentFrameIndex)") }
        player.play()
        await player.waitUntilFull()

        var shown = [player.currentFrameIndex]
        for _ in 0..<12 {
            clock.tick(0.1)
            shown.append(player.currentFrameIndex)
        }

        // THEN it ends where it started, not a frame short of it
        #expect(shown == [0, 1, 2, 3, 2, 1, 0, 1, 2, 3, 2, 1, 0])
        #expect(!player.isFinished)
        clock.tick(0.1)
        #expect(player.isFinished)
        #expect(player.isPlaying == false)
        #expect(player.currentFrameIndex == 0)
        #expect(player.completedLoopCount == 2)
        #expect(events == ["loop 1 on frame 0", "loop 2 on frame 0", "finish on frame 0"])
    }

    @Test(arguments: [AnimatedImagePlayer.PlaybackMode.forward, .reverse, .bounce])
    func theLoopCountOfTheFileIsHonored(_ mode: AnimatedImagePlayer.PlaybackMode) async {
        // GIVEN a file that asks to be played twice, whichever way
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = mode
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, loopCount: 2, options: options, pool: pool)
        player.play()
        await player.waitUntilFull()

        var ticks = 0
        while !player.isFinished, ticks < 100 {
            clock.tick(0.1)
            ticks += 1
        }

        #expect(player.completedLoopCount == 2)
        #expect(ticks == (mode == .bounce ? 9 : 6))
    }

    @Test func aBounceWithALoopOfTwoFramesEndsOnTheFirst() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .bounce
        options.loopCount = .finite(1)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 2, options: options, pool: pool)
        player.play()
        await player.waitUntilFull()

        var shown = [player.currentFrameIndex]
        for _ in 0..<3 {
            clock.tick(0.1)
            shown.append(player.currentFrameIndex)
        }

        #expect(shown == [0, 1, 0, 0])
        #expect(player.isFinished)
        #expect(player.completedLoopCount == 1)
    }

    // MARK: Moving the Playhead

    @Test func restartGoesBackToTheFrameAReverseAnimationStartsOn() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        options.loopCount = .finite(1)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, options: options, pool: pool)
        player.play()
        await player.waitUntilFull()
        for _ in 0..<3 { clock.tick(0.1) }
        #expect(player.isFinished)

        player.restart()

        #expect(player.currentFrameIndex == 2)
        #expect(player.isPlaying)
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)
    }

    @Test func seekingTakesAnIndexIntoTheFileInReverseToo() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 6, options: options, pool: pool)
        player.play()
        await player.waitUntilFull()

        player.seek(toFrame: 2)

        #expect(player.currentFrameIndex == 2)
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)
    }

    @Test func aSeekLeavesABounceHeadingTheWayItWas() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .bounce
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 6, options: options, pool: pool)
        player.play()
        await player.waitUntilFull()

        // Heading out, it carries on heading out...
        player.seek(toFrame: 2)
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 3)

        // ...and once it has turned, it carries on coming back.
        player.seek(toFrame: 5)
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 4)
        player.seek(toFrame: 2)
        clock.tick(0.1)
        #expect(player.currentFrameIndex == 1)
    }

    @Test func aFinishedBounceCanBeSeekedAndPlayedAgain() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .bounce
        options.loopCount = .finite(1)
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 3, options: options, pool: pool)
        player.play()
        await player.waitUntilFull()
        for _ in 0..<5 { clock.tick(0.1) }
        #expect(player.isFinished)

        player.seek(toFrame: 0)
        player.play()

        var shown = [player.currentFrameIndex]
        for _ in 0..<4 {
            clock.tick(0.1)
            shown.append(player.currentFrameIndex)
        }
        #expect(shown == [0, 1, 2, 1, 0])
    }

    @Test func aPlayerThatTakesOverCarriesOnTheWayTheOtherWasHeading() async {
        // GIVEN a bounce on its way back, which is what a frame index alone
        // doesn't say
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .bounce
        let source = Test.animatedGIFSource(frameCount: 6)
        let (previous, clock) = makeIdlePlayer(source: source, options: options)
        previous.play()
        await previous.waitUntilFull()
        for _ in 0..<7 { clock.tick(0.1) } // Past the turn, on frame 3

        // WHEN a view that has grown replaces the player with one of its own
        options.isSynchronizationEnabled = false
        options.maxPixelSize = 4
        let (player, newClock) = makeIdlePlayer(source: source, options: options, pool: AnimatedImageFramePool())
        player.resume(from: previous)
        player.play()
        await player.waitUntilFull()

        // THEN it carries on coming back
        #expect(player.currentFrameIndex == 3)
        newClock.tick(0.1)
        #expect(player.currentFrameIndex == 2)
    }

    // MARK: The Clock

    @Test(arguments: [AnimatedImagePlayer.PlaybackMode.reverse, .bounce])
    func noFrameIsSkippedWhileTheDecoderIsBehind(_ mode: AnimatedImagePlayer.PlaybackMode) async throws {
        // GIVEN a decoder that hands over frames only when the test says so
        var options = AnimatedImagePlayer.Options.twoFrameBuffer
        options.playbackMode = mode
        let source = Test.animatedGIFSource(frameCount: 6)
        let decoder = GatedFrameDecoder(source: source, isGated: false)
        let (player, clock) = makeIdlePlayer(source: source, options: options, decoder: decoder)
        var shown: [Int] = []
        player.onFrame = { [unowned player] _ in shown.append(player.currentFrameIndex) }
        player.play()
        await player.waitUntilFull()
        #expect(!shown.isEmpty)

        // WHEN the clock runs ahead of the decoder over and over
        for _ in 0..<(player.order.loopLength * 2) {
            clock.tick(0.2)
            clock.tick(0.2)
            await player.waitUntilFull()
        }

        // THEN every frame came up in turn, late rather than never
        let expected = (0..<shown.count).map { player.order.frameIndex(at: $0) }
        #expect(shown == expected)
        #expect(shown.count >= player.order.loopLength)
    }

    @Test(arguments: [AnimatedImagePlayer.PlaybackMode.reverse, .bounce])
    func aStallMovesOnByOneFrame(_ mode: AnimatedImagePlayer.PlaybackMode) async {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = mode
        let (player, clock) = AnimatedImageTest.makePlayer(frameCount: 6, options: options, pool: pool)
        player.play()
        await player.waitUntilFull()
        let start = player.currentFrameIndex

        // The main thread was stopped for ten seconds: the animation stretches
        // instead of jumping to wherever it would have got to.
        clock.tick(10)

        #expect(player.currentFrameIndex == player.order.frameIndex(at: 1))
        #expect(player.currentFrameIndex != start)
        #expect(player.diagnostics.playbackTime == AnimatedImagePlayer.maxTimeStep)
    }

    @Test(arguments: [AnimatedImagePlayer.PlaybackMode.reverse, .bounce])
    func theClockRunsAtTheRateItDoesGoingForward(_ mode: AnimatedImagePlayer.PlaybackMode) async {
        for isThrottling in [false, true] {
            var options = AnimatedImagePlayer.Options()
            let (forward, forwardClock) = AnimatedImageTest.makePlayer(
                delays: [0.05, 0.1, 0.1, 0.1],
                options: options,
                power: AnimatedImagePowerMonitor(isThrottling: isThrottling)
            )
            options.playbackMode = mode
            let (player, clock) = AnimatedImageTest.makePlayer(
                delays: [0.05, 0.1, 0.1, 0.1],
                options: options,
                power: AnimatedImagePowerMonitor(isThrottling: isThrottling)
            )

            #expect(clock.preferredFrameRate == forwardClock.preferredFrameRate)
            #expect(clock.preferredFrameRate > 0)
            _ = (forward, player)
        }
    }

    // MARK: Helpers

    /// Plays the animation and returns the frame on screen after each of the
    /// given number of steps, the first of them being where it starts.
    private func shownFrames(of source: AnimatedImageSource, mode: AnimatedImagePlayer.PlaybackMode, count: Int) async -> [Int] {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = mode
        options.loopCount = .infinite
        let (player, clock) = AnimatedImageTest.makePlayer(source: source, options: options, pool: AnimatedImageFramePool())
        player.play()
        await player.waitUntilFull()

        var shown: [Int] = []
        for _ in 0..<count {
            shown.append(player.currentFrameIndex)
            step(player, clock)
        }
        return shown
    }

    /// Ticks for exactly as long as the frame on screen asks for, which is a
    /// hair over 0.1 s in the formats Image I/O reads the delays of in single
    /// precision.
    private func step(_ player: AnimatedImagePlayer, _ clock: ManualClock) {
        clock.tick(player.animation.delays[player.currentFrameIndex])
    }
}

/// What ``AnimatedImagePlayer/PlaybackMode`` costs: the order the decoder is
/// asked for the frames in, the memory they stay inside, and what the players
/// of one animation share.
@Suite(.timeLimit(.minutes(5))) @MainActor
struct AnimatedImagePlaybackCostTests: AnimatedImagePoolSuite {
    let pool = AnimatedImageFramePool()

    // MARK: What It Costs the Decoder

    @Test func anAnimationHeldWholeIsDecodedOnceInFileOrder() async {
        // GIVEN a GIF the pool can hold whole, played backward
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        let source = Test.animatedGIFSource(frameCount: 6)
        let decoder = GatedFrameDecoder(source: source, isGated: false)

        // WHEN the player fills up
        let (player, clock) = makeIdlePlayer(source: source, options: options, decoder: decoder)
        await player.waitUntilFull()
        player.play()
        await player.waitUntilFull()

        // THEN the decoder only ever moved forward, past the window it was
        // asked for while nobody was watching – frames from last to first
        // would have walked the file from the start for each one
        #expect(await decoder.startedIndexes == [4, 5, 0, 1, 2, 3])
        #expect(await decoder.decodeCount == 6)

        // AND a loop of it decodes nothing more
        for _ in 0..<12 { clock.tick(0.1) }
        await player.waitUntilFull()
        #expect(await decoder.decodeCount == 6)
        #expect(player.diagnostics.isFullyBuffered)
        #expect(player.diagnostics.bufferedFrameCount == 6)
    }

    @Test func aBounceHeldWholeIsDecodedOnce() async {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .bounce
        let source = Test.animatedGIFSource(frameCount: 6)
        let decoder = GatedFrameDecoder(source: source, isGated: false)
        let (player, clock) = makeIdlePlayer(source: source, options: options, decoder: decoder)
        player.play()
        await player.waitUntilFull()

        for _ in 0..<20 { clock.tick(0.1) }
        await player.waitUntilFull()

        #expect(await decoder.startedIndexes == [0, 1, 2, 3, 4, 5])
        #expect(await decoder.decodeCount == 6)
        #expect(player.diagnostics.bufferedFrameCount == 6)
    }

    @Test func aBounceHeadingBackReachesEveryFrame() async throws {
        // GIVEN a bounce on its way back, on a decoder asked in playback order
        let decoder = OrderRecordingDecoder(colors: Array(repeating: .red, count: 6))
        let animation = AnimatedImageSource(
            data: Data(),
            delays: Array(repeating: 0.1, count: 6),
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { _ in decoder }
        )
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .bounce
        let (player, clock) = makeIdlePlayer(source: try #require(animation), options: options)
        player.play()
        await player.waitUntilFull()
        for _ in 0..<7 { clock.tick(0.1) }
        #expect(player.currentFrameIndex == 3)
        await decoder.reset()

        // WHEN it has to fill up from there
        player.store.removeAllFrames()
        player.store.scheduleDecodeIfNeeded()
        await player.waitUntilFull()

        // THEN it gets every frame, although as many positions as there are
        // frames don't reach the far end from here, the nearest ones first
        #expect(await decoder.indexes == [3, 2, 1, 0, 4, 5])
        #expect(player.diagnostics.bufferedFrameCount == 6)
    }

    @Test func aFormatThatDecodesInAnyOrderIsAskedInPlaybackOrder() async throws {
        // GIVEN an animation with a decoder of its own, which nothing says has
        // to go forward: the first frame on screen shouldn't wait for the rest
        let frames = (0..<6).map { _ in SolidColor.red }
        let decoder = OrderRecordingDecoder(colors: frames)
        let animation = AnimatedImageSource(
            data: Data(),
            delays: Array(repeating: 0.1, count: 6),
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { _ in decoder }
        )
        let source = try #require(animation)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse

        let (player, _) = makeIdlePlayer(source: source, options: options)
        await player.waitUntilFull()
        player.play()
        await player.waitUntilFull()

        #expect(await decoder.indexes == [5, 4, 3, 2, 1, 0])
    }

    @Test func aHEICSequenceIsAskedInPlaybackOrder() async throws {
        let source = try PlaybackFixture.heics.makeSource()
        let decoder = GatedFrameDecoder(source: source, isGated: false)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse

        let (player, _) = makeIdlePlayer(source: source, options: options, decoder: decoder)
        await player.waitUntilFull()
        player.play()
        await player.waitUntilFull()

        #expect(await decoder.startedIndexes == [5, 4, 3, 2, 1, 0])
    }

    @Test(arguments: [
        ("gif", true), ("png", true), ("webp", true), ("avif", false)
    ])
    func whichFormatsGoForward(_ format: String, prefersFileOrder: Bool) throws {
        let data = switch format {
        case "gif": DeltaAnimation.gif()
        case "png": DeltaAnimation.apng()
        default: Test.data(name: "animated", extension: format)
        }
        let source = try #require(AnimatedImageSource(data: data))

        #expect(source.prefersDecodingInFileOrder == prefersFileOrder)
    }

    @Test func aDecoderOfYourOwnIsNotAssumedToGoForward() throws {
        let source = AnimatedImageSource(
            data: Data(),
            delays: [0.1, 0.1],
            size: CGSize(width: 8, height: 8),
            makeFrameDecoder: { _ in SolidColorFrameDecoder(id: "custom", color: .red) }
        )

        #expect(try #require(source).prefersDecodingInFileOrder == false)
    }

    // MARK: The Budget

    @Test(arguments: [AnimatedImagePlayer.PlaybackMode.reverse, .bounce])
    func aWindowStaysInsideThePool(_ mode: AnimatedImagePlayer.PlaybackMode) async throws {
        // GIVEN an animation of 12 frames and a pool with room for 3 of them
        let source = Test.animatedGIFSource(frameCount: 12)
        let limit = 3 * source.bytesPerFrame
        let pool = AnimatedImageFramePool(costLimit: limit)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = mode
        let (player, clock) = AnimatedImageTest.makePlayer(source: source, options: options, pool: pool)
        player.play()

        // WHEN it plays two loops
        var shown: [Int] = []
        for _ in 0..<(player.order.loopLength * 2) {
            await player.waitUntilFull()
            shown.append(player.currentFrameIndex)

            // THEN it never holds more than the pool has, nor loses a frame to
            // staying inside it
            #expect(pool.totalCost <= limit)
            #expect(player.diagnostics.bufferCapacity <= 3)
            clock.tick(0.1)
        }
        #expect(shown == (0..<shown.count).map { player.order.frameIndex(at: $0) })
    }

    @Test func playheadsOnOneFrameGoingOppositeWaysClaimTwoWindows() async throws {
        // GIVEN two players on the same frame of an animation that doesn't
        // fit, heading away from each other: one window by the playhead, two
        // by the frames they want
        let source = Test.animatedGIFSource(frameCount: 12)
        let limit = 3 * source.bytesPerFrame
        let pool = AnimatedImageFramePool(costLimit: limit)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        let (reverse, _) = AnimatedImageTest.makePlayer(source: source, options: .init(), pool: pool)
        let (forward, _) = AnimatedImageTest.makePlayer(source: source, options: options, pool: pool)
        reverse.play()
        forward.play()

        // WHEN both land on it
        reverse.seek(toFrame: 6)
        forward.seek(toFrame: 6)
        await reverse.waitUntilFull()

        // THEN the windows give way to what the pool can hold
        #expect(reverse.store === forward.store)
        #expect(reverse.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
        #expect(forward.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
        #expect(pool.totalCost <= limit)
    }

    @Test func oppositeWaysAskThePoolForTheFramesTheirWindowsCover() {
        let source = Test.animatedGIFSource(frameCount: 12)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        let forward = makePlayer(source: source)
        let reverse = makePlayer(source: source, options: options)
        let store = forward.store

        // On one frame, heading apart: two windows less the frame they share
        forward.seek(toFrame: 6)
        reverse.seek(toFrame: 6)
        #expect(store.leastDemand == store.byteCount(ofFrames: 5))

        // Heading toward each other over the same frames: one window
        forward.seek(toFrame: 5)
        reverse.seek(toFrame: 7)
        #expect(store.leastDemand == store.byteCount(ofFrames: 3))
    }

    @Test func playersOfOneAnimationHoldWhatTheyShareOnce() async throws {
        // GIVEN room for two windows of 3 and players on either side of frame
        // 6, going toward each other: their windows overlap
        let source = Test.animatedGIFSource(frameCount: 12)
        let limit = 6 * source.bytesPerFrame
        let pool = AnimatedImageFramePool(costLimit: limit)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        let (forward, _) = AnimatedImageTest.makePlayer(source: source, options: .init(), pool: pool)
        let (reverse, _) = AnimatedImageTest.makePlayer(source: source, options: options, pool: pool)
        forward.play()
        reverse.play()

        forward.seek(toFrame: 5) // 5, 6, 7
        reverse.seek(toFrame: 7) // 7, 6, 5
        await forward.waitUntilFull()

        #expect(forward.bufferCapacity == 3)
        #expect(reverse.bufferCapacity == 3)
        #expect(forward.store.decodedFrameCount(in: 5..<8) == 3)
        #expect(pool.totalCost == 3 * source.bytesPerFrame)
    }

    @Test func playingBothWaysStaysInsideThePool() async throws {
        // GIVEN a forward and a backward player, which cross twice a loop
        let source = Test.animatedGIFSource(frameCount: 12)
        let limit = 6 * source.bytesPerFrame
        let pool = AnimatedImageFramePool(costLimit: limit)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        let (forward, forwardClock) = AnimatedImageTest.makePlayer(source: source, options: .init(), pool: pool)
        let (reverse, reverseClock) = AnimatedImageTest.makePlayer(source: source, options: options, pool: pool)
        forward.play()
        reverse.play()

        for step in 0..<24 {
            await forward.waitUntilFull()
            await reverse.waitUntilFull()
            #expect(pool.totalCost <= limit)
            #expect(forward.currentFrameIndex == step % 12)
            #expect(reverse.currentFrameIndex == 11 - step % 12)
            forwardClock.tick(0.1)
            reverseClock.tick(0.1)
        }
    }

    @Test func aMemoryWarningHoldsABackwardPlayerAtTwoFrames() async throws {
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        let (player, clock) = makeIdlePlayer(source: Test.animatedGIFSource(frameCount: 12), options: options)
        player.play()
        await player.waitUntilFull()
        #expect(player.diagnostics.bufferedFrameCount == 12)

        pool.reduceMemoryUsage()
        await player.waitUntilFull()

        #expect(player.bufferCapacity == AnimatedImagePlayer.idleFrameCount)
        #expect(player.diagnostics.bufferedFrameCount == 2)
        clock.tick(0.1)
        await player.waitUntilFull()
        #expect(player.currentFrameIndex == 10)
        #expect(player.diagnostics.bufferedFrameCount == 2)
    }

    // MARK: Sharing

    @Test func oppositeWaysShareTheFramesAndNotThePlayhead() async throws {
        // GIVEN an animation playing forward
        let source = Test.animatedGIFSource(frameCount: 6)
        let decoder = GatedFrameDecoder(source: source, isGated: false)
        let (forward, forwardClock) = makeIdlePlayer(source: source, decoder: decoder)
        forward.play()
        await forward.waitUntilFull()
        for _ in 0..<2 { forwardClock.tick(0.1) }

        // WHEN a reverse player of the same animation joins
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        let (reverse, reverseClock) = makeIdlePlayer(source: source, options: options)
        reverse.play()

        // THEN it draws from the frames already there and decodes nothing...
        #expect(reverse.store === forward.store)
        #expect(pool.animationCount == 1)
        #expect(reverse.diagnostics.sharingPlayerCount == 2)
        #expect(reverse.image != nil)
        await reverse.waitUntilFull()
        #expect(await decoder.decodeCount == 6)

        // ...and neither knocks the other off its course
        #expect(forward.currentFrameIndex == 2)
        #expect(reverse.currentFrameIndex == 5)
        for step in 1...8 {
            forwardClock.tick(0.1)
            reverseClock.tick(0.1)
            #expect(forward.currentFrameIndex == (2 + step) % 6)
            #expect(reverse.currentFrameIndex == 5 - step % 6)
        }
    }

    @Test func aPlayerFallsInBehindOnlyTheOnesGoingItsWay() async throws {
        let source = Test.animatedGIFSource(frameCount: 8)
        var reverseOptions = AnimatedImagePlayer.Options()
        reverseOptions.playbackMode = .reverse
        let (leader, clock) = makeIdlePlayer(source: source, options: reverseOptions)
        leader.play()
        await leader.waitUntilFull()
        for _ in 0..<3 { clock.tick(0.1) }
        #expect(leader.currentFrameIndex == 4)

        // A player going the same way starts on the frame the other is on...
        let (follower, _) = makeIdlePlayer(source: source, options: reverseOptions)
        #expect(follower.currentFrameIndex == 4)

        // ...and one going the other way has nothing to fall in behind.
        let (forward, _) = makeIdlePlayer(source: source)
        #expect(forward.currentFrameIndex == 0)
    }

    @Test func aBounceFallsInBehindTheWayTheOtherIsHeading() async throws {
        // GIVEN a bounce on its way back through frame 3
        let source = Test.animatedGIFSource(frameCount: 6)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .bounce
        let (leader, clock) = makeIdlePlayer(source: source, options: options)
        leader.play()
        await leader.waitUntilFull()
        for _ in 0..<7 { clock.tick(0.1) }
        #expect(leader.currentFrameIndex == 3)

        // WHEN a second one joins
        let (follower, followerClock) = makeIdlePlayer(source: source, options: options)
        follower.play()

        // THEN they stay in step
        #expect(follower.currentFrameIndex == 3)
        for _ in 0..<8 {
            clock.tick(0.1)
            followerClock.tick(0.1)
            #expect(follower.currentFrameIndex == leader.currentFrameIndex)
        }
    }

    @Test func theStoreForgetsTheModeOfAPlayerThatHasGone() async throws {
        // A released player mustn't leave its store on the slower paths for
        // the ones that stayed. What that's worth is the arithmetic of the
        // forward path; what can be seen of it is that they still get windows.
        let source = Test.animatedGIFSource(frameCount: 12)
        let pool = AnimatedImageFramePool(costLimit: 6 * source.bytesPerFrame)
        var options = AnimatedImagePlayer.Options()
        options.playbackMode = .reverse
        var reverse: AnimatedImagePlayer? = AnimatedImageTest.makePlayer(source: source, options: options, pool: pool).player
        let (forward, _) = AnimatedImageTest.makePlayer(source: source, options: .init(), pool: pool)
        forward.play()
        reverse?.play()
        await forward.waitUntilFull()

        reverse = nil
        pool.rebalance()

        #expect(forward.diagnostics.sharingPlayerCount == 1)
        #expect(forward.bufferCapacity == 3)
    }
}

/// The arithmetic the frame store and the player lean on, against the slow way
/// of getting the same answers.
struct AnimatedImagePlaybackOrderTests {
    private typealias Order = AnimatedImagePlaybackOrder

    @Test(arguments: [AnimatedImagePlayer.PlaybackMode.forward, .reverse, .bounce], [2, 3, 4, 7])
    func aWindowCoversTheFramesItsPositionsShow(_ mode: AnimatedImagePlayer.PlaybackMode, frameCount: Int) {
        let order = Order(mode: mode, frameCount: frameCount)
        for position in 0..<order.loopLength {
            for length in 1...frameCount {
                let shown = Set((0..<length).map { order.frameIndex(at: position + $0) })
                for index in 0..<frameCount {
                    // Every frame is the whole animation, wherever it starts
                    let expected = shown.contains(index) || (mode == .bounce && length >= frameCount)
                    #expect(order.covers(index, from: position, length: length) == expected, "position \(position), length \(length), frame \(index)")
                }
            }
        }
    }

    @Test(arguments: [AnimatedImagePlayer.PlaybackMode.forward, .reverse, .bounce], [2, 3, 4, 7])
    func aPositionComesBackToTheFrameItWasAskedFor(_ mode: AnimatedImagePlayer.PlaybackMode, frameCount: Int) {
        let order = Order(mode: mode, frameCount: frameCount)
        for position in 0...order.loopLength {
            for index in 0..<frameCount {
                #expect(order.frameIndex(at: order.position(of: index, from: position)) == index)
            }
        }
    }

    @Test func aLoopHasAPositionForEveryFrameShown() {
        #expect(Order(mode: .forward, frameCount: 5).loopLength == 5)
        #expect(Order(mode: .reverse, frameCount: 5).loopLength == 5)
        #expect(Order(mode: .bounce, frameCount: 5).loopLength == 8)
        #expect(Order(mode: .bounce, frameCount: 2).loopLength == 2)
    }

    @Test func theEndOfABounceIsTheFrameItStartedOn() {
        let order = Order(mode: .bounce, frameCount: 4)
        #expect(order.frameIndex(at: order.loopLength) == 0)
    }
}

/// A decoder that remembers the order it was asked for the frames in.
private actor OrderRecordingDecoder: AnimatedImageFrameDecoding {
    private let colors: [SolidColor]
    private(set) var indexes: [Int] = []

    init(colors: [SolidColor]) {
        self.colors = colors
    }

    func decode(at index: Int) -> CGImage? {
        indexes.append(index)
        return colors[index].makeImage(size: CGSize(width: 8, height: 8))
    }

    func reset() {
        indexes = []
    }
}
