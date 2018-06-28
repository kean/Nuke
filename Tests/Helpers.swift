// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

private final class BundleToken {}

// Test data.
enum Test {
    static func data(name: String, extension ext: String) -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let URL = bundle.url(forResource: name, withExtension: ext)
        return try! Data(contentsOf: URL!)
    }

    static let url = URL(string: "http://test.com")!

    static let data: Data = Test.data(name: "fixture", extension: "jpeg")

    static let image: Image = {
        let data = Test.data(name: "fixture", extension: "jpeg")
        return Nuke.ImageDecoder().decode(data: data, isFinal: true)!
    }()

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
        urlResponse: urlResponse
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
