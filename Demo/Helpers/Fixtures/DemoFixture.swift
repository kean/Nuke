// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// An image the demo can serve without the network: drawn and encoded the
/// first time it is asked for, or shipped with the app for the formats Image
/// I/O can't write.
///
/// A fixture has a URL of its own, `demo-fixture://nuke/<name>`, which only
/// ``DemoFixtureLoader`` answers: `DemoPipelineProbe` hands every request for
/// one to the fixture loader, whatever loader the pipeline was configured
/// with. A `DataLoader` that got one anyway would fail it with
/// `URLError.unsupportedURL` rather than go to the network.
///
/// The generated ones are the same bytes on every run on a given system, which
/// is what makes a run on fixtures comparable to the last one. Each one says
/// what it is on its face – "FIXTURE 360×240" – so a screenshot shows where
/// its images came from.
///
/// The bundled one, in `Resources/Fixtures`, was drawn the same way and
/// encoded on a Mac: the animated WebP with
/// `img2webp -loop 0 -lossy -q 60 -d 100` from 50 frames.
enum DemoFixture: Hashable, Sendable {
    /// A stand-in for the photo at this index of the photo stream: 360×240,
    /// or 240×360 for every third one, like the photos it replaces.
    case photo(Int)
    /// A 12 MP JPEG, 4000×3000, for decoding and downsampling costs that
    /// show.
    case largeJPEG
    /// A 400×400 GIF, 60 frames of 30 ms.
    case gif
    /// A 300×300 GIF, 200 frames of 50 ms: more than the default frame
    /// buffer holds.
    case longGIF
    /// A 100×100 animated PNG, 20 frames of 75 ms: a ball bouncing on a
    /// transparent background.
    case apng
    /// A 300×225 animated WebP, 50 frames of 100 ms. Bundled.
    case animatedWebP
    /// A 96×96 GIF of four frames of 0, 10, 20, and 500 ms, for the delay
    /// map of **Animated Images**.
    case mixedDelayGIF
    /// A 56×26 NukePix file, the toy format of the Custom Decoder screen,
    /// which only its decoder reads.
    case nukePix
    /// The NukePix file cut off at 60%: the signature, and too few pixels.
    case truncatedNukePix

    /// The photos of the stream, one per URL in `photos.json`.
    static var photos: [DemoFixture] {
        DemoImages.Network.photos.indices.map { .photo($0) }
    }

    /// Every fixture but the photos.
    static let named: [DemoFixture] = [.largeJPEG, .gif, .longGIF, .apng, .animatedWebP, .mixedDelayGIF, .nukePix, .truncatedNukePix]

    // MARK: URLs

    static let scheme = "demo-fixture"
    private static let host = "nuke"

    /// The URL a request asks for the fixture with.
    var url: URL {
        URL(string: "\(Self.scheme)://\(Self.host)/\(name)")!
    }

    /// The fixture a URL names, whatever its query says, or `nil` for a URL
    /// that isn't a fixture's.
    init?(url: URL?) {
        guard let url, Self.isFixture(url) else { return nil }
        let name = url.lastPathComponent
        if let fixture = Self.named.first(where: { $0.name == name }) {
            self = fixture
        } else if name.hasPrefix("photo-"), name.hasSuffix(".jpeg"),
                  let index = Int(name.dropFirst("photo-".count).dropLast(".jpeg".count)),
                  DemoImages.Network.photos.indices.contains(index) {
            self = .photo(index)
        } else {
            return nil
        }
    }

    /// Whether the URL is a fixture's, one that only ``DemoFixtureLoader``
    /// answers.
    static func isFixture(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == scheme
    }

    // MARK: Description

    /// The last component of the URL.
    var name: String {
        switch self {
        case .photo(let index): "photo-\(index).jpeg"
        case .largeJPEG: "large.jpeg"
        case .gif: "animation.gif"
        case .longGIF: "long.gif"
        case .apng: "ball.png"
        case .animatedWebP: "animation.webp"
        case .mixedDelayGIF: "mixed-delay.gif"
        case .nukePix: "badge.nukepix"
        case .truncatedNukePix: "truncated.nukepix"
        }
    }

    /// The MIME type the fixture loader reports.
    var mimeType: String {
        switch self {
        case .photo, .largeJPEG: "image/jpeg"
        case .apng: "image/png"
        case .gif, .longGIF, .mixedDelayGIF: "image/gif"
        case .animatedWebP: "image/webp"
        case .nukePix, .truncatedNukePix: "image/x-nukepix"
        }
    }

    /// The size of the stand-in for the photo at `index`: landscape, with
    /// every third one portrait, the way the stream mixes them.
    static func photoSize(at index: Int) -> (width: Int, height: Int) {
        index % 3 == 2 ? (240, 360) : (360, 240)
    }
}

/// Why ``DemoFixtureLoader`` couldn't answer a request.
enum DemoFixtureError: Error, LocalizedError, CustomStringConvertible {
    /// No fixture has the URL.
    case noFixture(URL?)
    /// A bundled fixture isn't in the app bundle.
    case missingResource(String)
    /// Image I/O couldn't encode a generated fixture.
    case encodingFailed(DemoFixture)

    var errorDescription: String? {
        switch self {
        case .noFixture(let url):
            "No fixture has the URL \(url?.absoluteString ?? "a request without a URL")."
        case .missingResource(let name):
            "The bundled fixture \(name) isn't in the app bundle."
        case .encodingFailed(let fixture):
            "Image I/O couldn't encode the fixture \(fixture.name)."
        }
    }

    /// The description, which is what `ImagePipeline.Error` prints.
    var description: String {
        errorDescription ?? "\(Self.self)"
    }
}
