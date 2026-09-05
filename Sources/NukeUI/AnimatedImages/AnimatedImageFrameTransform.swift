// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Nuke

/// A transformation applied to every frame of an animation as it is decoded.
///
/// ```swift
/// var options = AnimatedImagePlayer.Options()
/// options.frameTransform = AnimatedImageFrameTransform(identifier: "grayscale") {
///     $0.copy(colorSpace: CGColorSpaceCreateDeviceGray())
/// }
/// ```
///
/// A ``Nuke/ImageProcessing`` processor doesn't reach the frames: it produces
/// a new image the encoded animation no longer describes, and the pipeline
/// drops the animation along with the data – see <doc:AnimatedImages>. This is
/// the hook for the case where the frames themselves should be tinted,
/// rounded, or drawn into, and playback should continue.
///
/// The transform runs on the decoder, off the main actor, once per decoded
/// frame – which for an animation too large to hold in memory is once per
/// frame per loop. Keep it to what a frame's worth of time affords.
public struct AnimatedImageFrameTransform: Sendable {
    /// Identifies what the transform produces.
    ///
    /// Every player showing one animation at one size draws from a single set
    /// of decoded frames, and this is what keeps two different transforms from
    /// sharing one: players whose identifiers match share frames, players
    /// whose identifiers differ each get a set of their own, decoded and held
    /// separately. Give two transforms the same identifier only when they
    /// produce the same pixels, and fold the parameters into it – a corner
    /// radius, a tint – the way ``Nuke/ImageProcessing/identifier`` does.
    public let identifier: String

    /// Returns the image to display in place of the decoded frame, or `nil` to
    /// display the decoded frame unchanged.
    public let transform: @Sendable (CGImage) -> CGImage?

    /// Creates a transform.
    ///
    /// - parameter identifier: What the transform produces, for frame sharing.
    /// - parameter transform: Returns the image to display in place of the
    /// decoded frame, or `nil` to leave the frame as it is – which is what a
    /// transform that fails should return, so that playback continues.
    public init(identifier: String, transform: @escaping @Sendable (CGImage) -> CGImage?) {
        self.identifier = identifier
        self.transform = transform
    }
}

/// Applies a transform to the frames another decoder produces.
///
/// An actor so that the transform runs off the main actor whatever the decoder
/// it wraps is isolated to.
actor AnimatedImageFrameTransformer: AnimatedImageFrameDecoding {
    private let decoder: any AnimatedImageFrameDecoding
    private let transform: AnimatedImageFrameTransform

    init(decoder: any AnimatedImageFrameDecoding, transform: AnimatedImageFrameTransform) {
        self.decoder = decoder
        self.transform = transform
    }

    func decode(at index: Int) async -> CGImage? {
        guard let frame = await decoder.decode(at: index) else {
            return nil
        }
        // The transform passed on this frame, or failed.
        return transform.transform(frame) ?? frame
    }
}
