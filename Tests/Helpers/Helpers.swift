// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Nuke
import Foundation
import CoreGraphics

#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

private final class BundleToken {}

// Test data.
enum Test {
    static func url(forResource name: String, extension ext: String) -> URL {
        let bundle = Bundle(for: BundleToken.self)
        return bundle.url(forResource: name, withExtension: ext)!
    }

    static func data(name: String, extension ext: String) -> Data {
        let url = self.url(forResource: name, extension: ext)
        return try! Data(contentsOf: url)
    }

    static func image(named name: String) -> PlatformImage {
        let components = name.split(separator: ".")
        return self.image(named: String(components[0]), extension: String(components[1]))
    }

    static func image(named name: String, extension ext: String) -> PlatformImage {
        Test.container(named: name, extension: ext).image
    }

    static func container(named name: String, extension ext: String) -> ImageContainer {
        let data = Test.data(name: name, extension: ext)
        return try! ImageDecoders.Default().decode(data)
    }

    static let url = URL(string: "http://test.com/example.jpeg")!

    static let data: Data = Test.data(name: "fixture", extension: "jpeg")

    // Test.image size is 640 x 480 pixels
    static var image: PlatformImage {
        Test.image(named: "fixture", extension: "jpeg")
    }

    // Device RGB image of the given size filled with a solid color, opaque
    // unless the alpha info says otherwise.
    static func rgbImage(
        width: Int,
        height: Int,
        color: CGColor = CGColor(red: 0, green: 0, blue: 1, alpha: 1),
        alphaInfo: CGImageAlphaInfo = .noneSkipLast
    ) -> PlatformImage {
        platformImage(makeImage(width: width, height: height, alphaInfo: alphaInfo, color: color)!)
    }

    // Grayscale (monochrome color space) image for color-space-sensitive paths.
    static func grayscaleImage(width: Int, height: Int) -> PlatformImage {
        let gray = CGColorSpaceCreateDeviceGray()
        return platformImage(makeImage(width: width, height: height, colorSpace: gray, alphaInfo: .none, color: CGColor(gray: 0.5, alpha: 1))!)
    }

    // Test.image size is 640 x 480 pixels
    static var container: ImageContainer {
        ImageContainer(image: image)
    }

    static var request: ImageRequest {
        ImageRequest(url: Test.url)
    }

    static let urlResponse = HTTPURLResponse(
        url: Test.url,
        mimeType: "jpeg",
        expectedContentLength: 22_789,
        textEncodingName: nil
    )

    static let response = ImageResponse(
        container: .init(image: Test.image),
        request: Test.request,
        urlResponse: urlResponse,
        cacheType: nil
    )
}

extension ImageDecodingContext {
    static var mock: ImageDecodingContext {
        mock(data: Test.data)
    }

    static func mock(data: Data, isCompleted: Bool = true, previewPolicy: ImagePipeline.PreviewPolicy = .incremental) -> ImageDecodingContext {
        ImageDecodingContext(request: Test.request, data: data, isCompleted: isCompleted, previewPolicy: previewPolicy)
    }
}

extension ImageProcessingContext {
    static var mock: ImageProcessingContext {
        ImageProcessingContext(request: Test.request, response: Test.response, isCompleted: true)
    }
}

#if os(macOS)
extension NSImage {
    var cgImage: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
#endif

extension CGImage {
    var size: CGSize {
        CGSize(width: width, height: height)
    }
}

extension PlatformImage {
    var sizeInPixels: CGSize {
        cgImage!.size
    }
}

func _groups(regex: String, in text: String) -> [String] {
    do {
        let regex = try NSRegularExpression(pattern: regex)
        let results = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return results.map {
            String(text[Range($0.range(at: 1), in: text)!])
        }
    } catch let error {
        print("invalid regex: \(error.localizedDescription)")
        return []
    }
}

// Supports subranges as well.
func _createChunks(for data: Data, size: Int) -> [Data] {
    var chunks = [Data]()
    let endIndex = data.endIndex
    var offset = data.startIndex
    while offset < endIndex {
        let chunkSize = offset + size > endIndex ? endIndex - offset : size
        let chunk = data[(offset)..<(offset + chunkSize)]
        offset += chunkSize
        chunks.append(chunk)
    }
    return chunks
}

/// A directory in the temporary folder that no other test uses.
func makeUniqueDirectoryURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("NukeTests-\(UUID().uuidString)", isDirectory: true)
}

/// A seeded generator, so a randomized sequence of operations is the same on
/// every run and a failure reproduces.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Result extension

extension Result {
    var isSuccess: Bool {
        return value != nil
    }

    var isFailure: Bool {
        return error != nil
    }

    var value: Success? {
        switch self {
        case let .success(value):
            return value
        case .failure:
            return nil
        }
    }

    var error: Failure? {
        switch self {
        case .success:
            return nil
        case let .failure(error):
            return error
        }
    }
}
