// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

/// The images used across the demo.
///
/// Everything is loaded over the network so that the demo exercises the same
/// code paths an app does: `URLSession`, disk cache, decoding, and processing.
/// The one exception is ``animatedHEIC``, which ships with the demo.
///
/// While ``DemoFixtureMode`` is offline, every URL here is the URL of the
/// ``DemoFixture`` that stands in for it, read when the screen asks: a screen
/// opened offline loads fixtures, and caches them apart from the photos.
/// ``Network`` has the network URLs whatever the mode.
enum DemoImages {
    /// A large landscape photo. Used by the screens that show a single image.
    static var landscape: URL { url(Network.landscape, .jpeg) }

    /// The same photo encoded as a progressive JPEG.
    static var progressiveJPEG: URL { url(Network.progressiveJPEG, .progressiveJPEG) }

    /// The same photo encoded as a baseline JPEG.
    static var baselineJPEG: URL { url(Network.baselineJPEG, .jpeg) }

    static var png: URL { url(Network.png, .png) }

    static var gif: URL { url(Network.gif, .gif) }

    /// An APNG.
    static var apng: URL { url(Network.apng, .apng) }

    /// An animated WebP.
    static var animatedWebP: URL { url(Network.animatedWebP, .animatedWebP) }

    /// A long, large GIF. Its frames don't all fit in the default buffer, so it
    /// is the one that shows the sliding window doing its job.
    static var largeGIF: URL { url(Network.largeGIF, .longGIF) }

    /// An animated HEIC – a HEIF image sequence – shipped with the demo, since
    /// there is no well-known URL for one. The format is worth having on screen
    /// because it is the one an app is most likely to get wrong: the file leads
    /// with the `msf1` brand, and Image I/O reports it as `public.heics`.
    ///
    /// A file URL, which the pipeline reads without a data loader, so it is
    /// the same offline.
    static let animatedHEIC = Bundle.main.url(forResource: "animated", withExtension: "heics")

    static var webp: URL { url(Network.webp, .webp) }

    static var video: URL { url(Network.video, .video) }

    /// A URL that always fails. Used to demonstrate the failure states.
    static var failing: URL { url(Network.failing, .missing) }

    /// A few photos used as avatars. The processors crop them to a square.
    static var avatars: [URL] { Array(photos.prefix(6)) }

    /// A photo stream used by the grid, prefetching, and stress-test screens.
    static var photos: [URL] {
        photos(from: DemoFixtureMode.isOffline ? .fixtures : .network)
    }

    /// The photo stream from the given source, whatever the mode. Offline, the
    /// network URLs are answered by fixtures all the same.
    static func photos(from source: DemoImageSource) -> [URL] {
        switch source {
        case .fixtures: fixturePhotos
        case .network: Network.photos
        }
    }

    private static let fixturePhotos = DemoFixture.photos.map(\.url)

    private static func url(_ url: URL, _ fixture: DemoFixture) -> URL {
        DemoFixtureMode.isOffline ? fixture.url : url
    }

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
/// Catalog screens load ``DemoImages/photos``, which follows
/// ``DemoFixtureMode``. A Lab screen that loads photos offers this choice
/// instead, and starts on fixtures, so that a run measures the pipeline rather
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
