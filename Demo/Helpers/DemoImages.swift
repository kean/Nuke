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
    static let landscape = URL(string: "https://user-images.githubusercontent.com/1567433/59150453-178bbb80-8a24-11e9-94ca-fd8dff6e2a9a.jpeg")!

    /// The same photo encoded as a progressive JPEG.
    static let progressiveJPEG = URL(string: "https://user-images.githubusercontent.com/1567433/120257587-7fb1b880-c25e-11eb-93d1-7e7df2b9f5ca.jpeg")!

    /// The same photo encoded as a baseline JPEG.
    static let baselineJPEG = URL(string: "https://user-images.githubusercontent.com/1567433/120257591-80e2e580-c25e-11eb-8032-54f3a966aedb.jpeg")!

    static let png = URL(string: "https://user-images.githubusercontent.com/1567433/114792417-57c1d080-9d56-11eb-8035-dc07cfd7557f.png")!

    static let gif = URL(string: "https://cloud.githubusercontent.com/assets/1567433/6505557/77ff05ac-c2e7-11e4-9a09-ce5b7995cad0.gif")!

    /// An APNG.
    static let apng = URL(string: "https://upload.wikimedia.org/wikipedia/commons/1/14/Animated_PNG_example_bouncing_beach_ball.png")!

    /// An animated WebP.
    static let animatedWebP = URL(string: "https://www.gstatic.com/webp/animated/1.webp")!

    /// A long, large GIF. Its frames don't all fit in the default buffer, so it
    /// is the one that shows the sliding window doing its job.
    static let largeGIF = URL(string: "https://upload.wikimedia.org/wikipedia/commons/2/2c/Rotating_earth_%28large%29.gif")!

    /// An animated HEIC – a HEIF image sequence – shipped with the demo, since
    /// there is no well-known URL for one. The format is worth having on screen
    /// because it is the one an app is most likely to get wrong: the file leads
    /// with the `msf1` brand, and Image I/O reports it as `public.heics`.
    static let animatedHEIC = Bundle.main.url(forResource: "animated", withExtension: "heics")

    static let webp = URL(string: "https://kean.github.io/images/misc/4.webp")!

    static let video = URL(string: "https://kean.github.io/videos/cat_video.mp4")!

    /// A URL that always fails. Used to demonstrate the failure states.
    static let failing = URL(string: "https://kean.github.io/images/this-image-does-not-exist.jpeg")!

    /// A few photos used as avatars. The processors crop them to a square.
    static let avatars = Array(photos.prefix(6))

    /// A photo stream used by the grid, prefetching, and stress-test screens.
    static let photos: [URL] = {
        let host = "https://cloud.githubusercontent.com/assets/1567433"
        return [
            "9781817/ecb16e82-57a0-11e5-9b43-6b4f52659997",
            "9781832/0719dd5e-57a1-11e5-9324-9764de25ed47",
            "9781833/09021316-57a1-11e5-817b-85b57a2a8a77",
            "9781834/0931ad74-57a1-11e5-9080-c8f6ecea19ce",
            "9781838/0e6274f4-57a1-11e5-82fd-872e735eea73",
            "9781839/0e63ad92-57a1-11e5-8841-bd3c5ea1bb9c",
            "9781843/0f4064b2-57a1-11e5-9fb7-f258e81a4214",
            "9781840/0e95f978-57a1-11e5-8179-36dfed72f985",
            "9781841/0e96b5fc-57a1-11e5-82ae-699b113bb85a",
            "9781894/839cf99c-57a1-11e5-9602-d56d99a31abc",
            "9781896/83c5e1f4-57a1-11e5-9961-97730da2a7ad",
            "9781897/83c622cc-57a1-11e5-98dd-3a7d54b60170",
            "9781900/83cbc934-57a1-11e5-8152-e9ecab92db75",
            "9781899/83cb13a4-57a1-11e5-88c4-48feb134a9f0",
            "9781898/83c85ba0-57a1-11e5-8569-778689bff1ed",
            "9781895/83b7f3fa-57a1-11e5-8579-e2fd6098052d",
            "9781901/83d5d500-57a1-11e5-9894-78467657874c",
            "9781902/83df3b72-57a1-11e5-82b0-e6eb08915402",
            "9781903/83e400bc-57a1-11e5-881d-c0ed2c5136f6",
            "9781964/f4553bea-57a1-11e5-9abf-f23470a5efc1",
            "9781955/f3b2ed18-57a1-11e5-8fc7-0579e44de0b0",
            "9781959/f3b7e624-57a1-11e5-8982-8017f53a4898",
            "9781957/f3b52e98-57a1-11e5-9f1a-8741acddb12d",
            "9781958/f3b5544a-57a1-11e5-880a-478507b2e189",
            "9781956/f3b35082-57a1-11e5-9d2f-2c364e3f9b68",
            "9781963/f3da11b8-57a1-11e5-838e-c75e6b00f33e",
            "9781961/f3d865de-57a1-11e5-87fd-bb8f28515a16",
            "9781960/f3d7f306-57a1-11e5-833f-f3802344619e",
            "9781962/f3d98c20-57a1-11e5-838e-10f9d20fbc9b",
            "9781982/2b67875a-57a2-11e5-91b2-ec4ca2a65674",
            "9781985/2b92e576-57a2-11e5-955f-73889423b552",
            "9781986/2b94c288-57a2-11e5-8ebd-4cc107444e70",
            "9781987/2b94ba72-57a2-11e5-8259-8d4b5fce1f6c",
            "9781984/2b9244ea-57a2-11e5-89b1-edc6922d1909",
            "9781988/2b94f32a-57a2-11e5-94f6-2c68c15f711f",
            "9781983/2b80e9ca-57a2-11e5-9a90-54884428affe",
            "9781989/2b9d462e-57a2-11e5-8c5c-d005e79e0070",
            "9781990/2babeeae-57a2-11e5-828d-6c050683274d",
            "9781991/2bb13a94-57a2-11e5-8a70-1d7e519c1631",
            "9781992/2bb2161c-57a2-11e5-8715-9b7d2df58708",
            "9781993/2bb397a8-57a2-11e5-853d-4d4f1854d1fe",
            "9781994/2bb61e88-57a2-11e5-8e45-bc2ed096cf97",
            "9781995/2bbdf73e-57a2-11e5-8847-afb709e28495",
            "9781996/2bc90a66-57a2-11e5-9154-6cc3a08a3e93",
            "9782000/2bd232a8-57a2-11e5-8617-eaff327b927f",
            "9781997/2bced964-57a2-11e5-9021-970f1f92608e",
            "9781998/2bd0def8-57a2-11e5-850f-e60701db4f62",
            "9781999/2bd2551c-57a2-11e5-82e3-54bb80f7c114",
            "9782001/2bdb5bb2-57a2-11e5-8a18-05fe673e2315",
            "9782002/2be52ed0-57a2-11e5-8e12-2f6e17787553",
            "9782003/2bed36de-57a2-11e5-9d4f-7c214e828fe6",
            "9782004/2bef8ed4-57a2-11e5-8949-26e1b80a0ebb",
            "9782005/2bf08622-57a2-11e5-86e2-c5d71ef615e9",
            "9782006/2bf2d968-57a2-11e5-8f44-3cd169219e78",
            "9782007/2bf5e95a-57a2-11e5-9b7a-96f355a5334b",
            "9782008/2c04b458-57a2-11e5-9381-feb4ae365a1d",
            "9782011/2c0e4054-57a2-11e5-89f0-7c91bb0e01a2",
            "9782009/2c0c4254-57a2-11e5-984d-0e44cc762219",
            "9782010/2c0ca730-57a2-11e5-834c-79153b496d44",
            "9782012/2c1277e6-57a2-11e5-862a-ec0c8fad727a",
            "9782122/543bc690-57a3-11e5-83eb-156108681377",
            "9782128/546af1f4-57a3-11e5-8ad6-78527accf642",
            "9782127/546ae2cc-57a3-11e5-9ad5-f0c7157eda5b",
            "9782124/5468528c-57a3-11e5-9cf9-89f763b473b4",
            "9782126/5468cf50-57a3-11e5-9d97-c8fc94e7b9a4",
            "9782125/54687d66-57a3-11e5-860f-c66597fd212c",
            "9782123/545728cc-57a3-11e5-83ab-51462737c19d",
            "9782129/54737694-57a3-11e5-9e1e-b626db67e625",
            "9782130/5483fee2-57a3-11e5-8928-e7706c765016",
            "9782133/54dd0c62-57a3-11e5-85ee-a02c1b9dd223",
            "9782131/54872b30-57a3-11e5-8903-db1f81ea1abb",
            "9782132/548a3b9a-57a3-11e5-8228-8ee523e7809e"
        ].map { URL(string: "\(host)/\($0).jpg")! }
    }()
}
