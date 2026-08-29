// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import NukeVideo // Deliberately the only Nuke import in this file.

/// NukeVideo extends Nuke types, so `import NukeVideo` has to be enough to use
/// it. These tests stop compiling if the re-export is removed.
@Suite
struct NukeVideoExportsTests {
    @Test func assetType() {
        #expect(AssetType.mp4.isVideo)
        #expect(!AssetType.jpeg.isVideo)
    }

#if !os(watchOS) && !os(visionOS)
    @Test func videoDecoder() {
        let makeDecoder: (ImageDecodingContext) -> (any ImageDecoding)? = {
            ImageDecoders.Video(context: $0)
        }
        let key: ImageContainer.UserInfoKey = .videoAssetKey

        #expect(key.rawValue == "com.github/kean/nuke/video-asset")
        withExtendedLifetime(makeDecoder) {}
    }
#endif
}
