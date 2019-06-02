// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

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

    static let url = URL(string: "http://test.com")!

    static let data: Data = Test.data(name: "fixture", extension: "jpeg")

    // Test.image size is 640 x 480 pixels
    static var image: Image {
        let data = Test.data(name: "fixture", extension: "jpeg")
        return Nuke.ImageDecoder().decode(data: data)!
    }

    static let request = ImageRequest(
        url: Test.url
    )

    static let urlResponse = HTTPURLResponse(
        url: Test.url,
        mimeType: "jpeg",
        expectedContentLength: 22_789,
        textEncodingName: nil
    )

    static let response = ImageResponse(
        image: Test.image,
        urlResponse: urlResponse,
        scanNumber: nil
    )
}

extension String: Error {}

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
