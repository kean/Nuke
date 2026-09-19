// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// The images used across the demo.
///
/// Everything is loaded over the network so that the demo exercises the same
/// code paths an app does: `URLSession`, disk cache, decoding, and processing.
/// The one exception is ``animatedHEIC``, which ships with the demo.
enum DemoImages {
    /// A large landscape photo. Used by the screens that show a single image.
    static let landscape = Network.landscape

    /// The same photo encoded as a progressive JPEG.
    static let progressiveJPEG = Network.progressiveJPEG

    /// The same photo encoded as a baseline JPEG.
    static let baselineJPEG = Network.baselineJPEG

    static let png = Network.png

    static let gif = Network.gif

    /// An APNG.
    static let apng = Network.apng

    /// An animated WebP.
    static let animatedWebP = Network.animatedWebP

    /// A long, large GIF. Its frames don't all fit in the default buffer, so it
    /// is the one that shows the sliding window doing its job.
    static let largeGIF = Network.largeGIF

    /// An animated HEIC – a HEIF image sequence – shipped with the demo, since
    /// there is no well-known URL for one. The format is worth having on screen
    /// because it is the one an app is most likely to get wrong: the file leads
    /// with the `msf1` brand, and Image I/O reports it as `public.heics`.
    ///
    /// A file URL, which the pipeline reads without a data loader.
    static let animatedHEIC = Bundle.main.url(forResource: "animated", withExtension: "heics")

    static let webp = Network.webp

    /// A photo taken with an iPhone, as its camera writes it: HEVC in a HEIF
    /// container that leads with the `heic` brand.
    static let heic = Network.heic

    static let video = Network.video

    /// A URL that always fails. Used to demonstrate the failure states.
    static let failing = Network.failing

    /// A few photos used as avatars. The processors crop them to a square.
    static var avatars: [URL] { Array(photos.prefix(6)) }

    /// A photo stream used by the grid, prefetching, and stress-test screens.
    static var photos: [URL] { Network.photos }

    /// The photo stream from the given source.
    static func photos(from source: DemoImageSource) -> [URL] {
        switch source {
        case .fixtures: fixturePhotos
        case .network: Network.photos
        }
    }

    private static let fixturePhotos = DemoFixture.photos.map(\.url)

    /// The URLs on the network.
    enum Network {
        static let landscape = URL(string: "https://user-images.githubusercontent.com/1567433/59150453-178bbb80-8a24-11e9-94ca-fd8dff6e2a9a.jpeg")!
        static let progressiveJPEG = URL(string: "https://user-images.githubusercontent.com/1567433/120257587-7fb1b880-c25e-11eb-93d1-7e7df2b9f5ca.jpeg")!
        static let baselineJPEG = URL(string: "https://user-images.githubusercontent.com/1567433/120257591-80e2e580-c25e-11eb-8032-54f3a966aedb.jpeg")!
        static let png = URL(string: "https://user-images.githubusercontent.com/1567433/114792417-57c1d080-9d56-11eb-8035-dc07cfd7557f.png")!
        static let gif = URL(string: "https://cloud.githubusercontent.com/assets/1567433/6505557/77ff05ac-c2e7-11e4-9a09-ce5b7995cad0.gif")!
        static let apng = URL(string: "https://upload.wikimedia.org/wikipedia/commons/1/14/Animated_PNG_example_bouncing_beach_ball.png")!
        static let animatedWebP = URL(string: "https://www.gstatic.com/webp/animated/1.webp")!
        static let largeGIF = URL(string: "https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif")!
        static let webp = URL(string: "https://kean.blog/images/misc/4.webp")!
        static let video = URL(string: "https://kean.blog/videos/cat_video.mp4")!
        /// A file of Nuke's own tests, at a release tag, so its bytes never
        /// change.
        static let heic = URL(string: "https://raw.githubusercontent.com/kean/Nuke/13.2.0/Tests/Resources/img_751.heic")!
        static let failing = URL(string: "https://kean.blog/images/this-image-does-not-exist.jpeg")!

        /// The photo stream. The URLs are in `photos.json`, in the demo's
        /// resources, so the stream can be edited without touching the code.
        static let photos: [URL] = {
            guard let url = Bundle.main.url(forResource: "photos", withExtension: "json") else {
                fatalError("photos.json is missing from the app bundle.")
            }
            do {
                return try JSONDecoder().decode([URL].self, from: Data(contentsOf: url))
            } catch {
                fatalError("photos.json isn't an array of URLs: \(error)")
            }
        }()
    }
}

/// Where a screen's photos come from.
///
/// Catalog screens load ``DemoImages/photos`` from the network. A Lab screen
/// that loads photos offers this choice instead, and starts on fixtures, so that a run measures the pipeline rather
/// than the network and compares with the last one.
enum DemoImageSource: String, CaseIterable, Identifiable {
    case fixtures
    case network

    var id: Self { self }

    var title: String {
        switch self {
        case .fixtures: "Fixtures"
        case .network: "Network"
        }
    }
}
