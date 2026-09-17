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
/// what it is on its face – "FIXTURE 360×240" – so a screenshot shows which
/// mode it was taken in.
///
/// The bundled ones, in `Resources/Fixtures`, were drawn the same way and
/// encoded on a Mac: the animated WebP with
/// `img2webp -loop 0 -lossy -q 60 -d 100` from 50 frames, the still WebP with
/// `cwebp -q 70`, and the video with `AVAssetWriter` (H.264, 30 fps, 120 kbps).
enum DemoFixture: Hashable, Sendable {
    /// A stand-in for the photo at this index of the photo stream: 360×240,
    /// or 240×360 for every third one, like the photos it replaces.
    case photo(Int)
    /// A 1440×960 baseline JPEG, the size of the landscape photo.
    case jpeg
    /// The same picture as ``jpeg``, encoded as a progressive JPEG with ten
    /// scans. ``DemoFixtureLoader`` delivers it a scan at a time.
    case progressiveJPEG
    /// A 12 MP JPEG, 4000×3000, for decoding and downsampling costs that
    /// show.
    case largeJPEG
    /// An 840×510 PNG with transparency.
    case png
    /// A 400×400 GIF, 60 frames of 30 ms.
    case gif
    /// A 300×300 GIF, 200 frames of 50 ms: more than the default frame
    /// buffer holds.
    case longGIF
    /// A 100×100 animated PNG, 20 frames of 75 ms: a ball bouncing on a
    /// transparent background.
    case apng
    /// A 1024×772 WebP. Bundled.
    case webp
    /// A 1008×756 HEIC still, the size of the iPhone photo it stands in for.
    /// Image I/O encodes it, so the encoder of the system it runs on decides
    /// its bytes.
    case heic
    /// A 300×225 animated WebP, 50 frames of 100 ms. Bundled.
    case animatedWebP
    /// A 320×240 H.264 video, 2 seconds. Bundled.
    case video
    /// Fails the way a missing image on a server does: with
    /// `DataLoader.Error.statusCodeUnacceptable(404)`, and no data.
    case missing
    /// An input of the Fixture Zoo, most of them not images a decoder should
    /// accept. Not in ``all``: the Fixture Zoo lists them.
    case zoo(DemoZooInput)

    /// The photos of the stream, one per URL in `photos.json`.
    static var photos: [DemoFixture] {
        DemoImages.Network.photos.indices.map { .photo($0) }
    }

    /// Every fixture, the photos included, in the order the Lab lists them.
    static var all: [DemoFixture] {
        named + photos
    }

    /// Every fixture but the photos.
    static let named: [DemoFixture] = [.jpeg, .progressiveJPEG, .largeJPEG, .png, .gif, .longGIF, .apng, .webp, .heic, .animatedWebP, .video, .missing]

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
        } else if name.hasPrefix(Self.zooPrefix), let input = DemoZooInput(rawValue: String(name.dropFirst(Self.zooPrefix.count))) {
            self = .zoo(input)
        } else if name.hasPrefix("photo-"), name.hasSuffix(".jpeg"),
                  let index = Int(name.dropFirst("photo-".count).dropLast(".jpeg".count)),
                  DemoImages.Network.photos.indices.contains(index) {
            self = .photo(index)
        } else {
            return nil
        }
    }

    private static let zooPrefix = "zoo-"

    /// Whether the URL is a fixture's, one that only ``DemoFixtureLoader``
    /// answers.
    static func isFixture(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == scheme
    }

    /// The fixture that stands in for one of the demo's network URLs while
    /// the demo is offline, or `nil` for a URL the demo doesn't know. The
    /// query is ignored, so a signed URL finds its photo.
    static func standIn(for url: URL) -> DemoFixture? {
        if let fixture = DemoFixture(url: url) {
            return fixture
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url.flatMap { standIns[$0] }
    }

    private static let standIns: [URL: DemoFixture] = {
        typealias Network = DemoImages.Network
        var standIns: [URL: DemoFixture] = [
            Network.landscape: .jpeg,
            Network.baselineJPEG: .jpeg,
            Network.progressiveJPEG: .progressiveJPEG,
            Network.png: .png,
            Network.gif: .gif,
            Network.largeGIF: .longGIF,
            Network.apng: .apng,
            Network.animatedWebP: .animatedWebP,
            Network.webp: .webp,
            Network.heic: .heic,
            Network.video: .video,
            Network.failing: .missing
        ]
        for (index, url) in Network.photos.enumerated() {
            standIns[url] = .photo(index)
        }
        return standIns
    }()

    // MARK: Description

    /// The last component of the URL.
    var name: String {
        switch self {
        case .photo(let index): "photo-\(index).jpeg"
        case .jpeg: "landscape.jpeg"
        case .progressiveJPEG: "progressive.jpeg"
        case .largeJPEG: "large.jpeg"
        case .png: "graphic.png"
        case .gif: "animation.gif"
        case .longGIF: "long.gif"
        case .apng: "ball.png"
        case .webp: "still.webp"
        case .heic: "photo.heic"
        case .animatedWebP: "animation.webp"
        case .video: "video.mp4"
        case .missing: "missing.jpeg"
        case .zoo(let input): Self.zooPrefix + input.fileName
        }
    }

    /// What it is, in a few words.
    var summary: String {
        switch self {
        case .photo(let index):
            let (width, height) = Self.photoSize(at: index)
            return "\(width)×\(height) JPEG"
        case .jpeg: return "1440×960 baseline JPEG"
        case .progressiveJPEG: return "1440×960 progressive JPEG"
        case .largeJPEG: return "4000×3000 JPEG"
        case .png: return "840×510 PNG with alpha"
        case .gif: return "400×400 GIF · 60 frames"
        case .longGIF: return "300×300 GIF · 200 frames"
        case .apng: return "100×100 APNG · 20 frames"
        case .webp: return "1024×772 WebP · bundled"
        case .heic: return "1008×756 HEIC"
        case .animatedWebP: return "300×225 WebP · 50 frames · bundled"
        case .video: return "320×240 MP4 · 2 s · bundled"
        case .missing: return "Fails with a 404"
        case .zoo(let input): return input.summary
        }
    }

    /// What it replaces while the demo is offline.
    var standsInFor: String {
        switch self {
        case .photo: "stands in for a photo of the stream"
        case .jpeg: "stands in for the landscape photo and its baseline copy"
        case .progressiveJPEG: "stands in for the progressive copy"
        case .largeJPEG: "for the Lab"
        case .png: "stands in for the PNG"
        case .gif: "stands in for the GIF"
        case .longGIF: "stands in for the large GIF"
        case .apng: "stands in for the APNG"
        case .webp: "stands in for the WebP"
        case .heic: "stands in for the HEIC photo"
        case .animatedWebP: "stands in for the animated WebP"
        case .video: "stands in for the video"
        case .missing: "stands in for the URL that always fails"
        case .zoo: "for the Fixture Zoo"
        }
    }

    /// The MIME type the fixture loader reports.
    var mimeType: String {
        switch self {
        case .photo, .jpeg, .progressiveJPEG, .largeJPEG, .missing: "image/jpeg"
        case .png, .apng: "image/png"
        case .gif, .longGIF: "image/gif"
        case .webp, .animatedWebP: "image/webp"
        case .heic: "image/heic"
        case .video: "video/mp4"
        case .zoo(let input): input.mimeType
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
    /// No fixture stands in for the URL.
    case noFixture(URL?)
    /// A bundled fixture isn't in the app bundle.
    case missingResource(String)
    /// Image I/O couldn't encode a generated fixture.
    case encodingFailed(DemoFixture)

    var errorDescription: String? {
        switch self {
        case .noFixture(let url):
            "No fixture stands in for \(url?.absoluteString ?? "a request without a URL"). Offline, the demo answers only the URLs in DemoImages; add a stand-in to DemoFixture to load another one."
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
