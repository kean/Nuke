// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

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

    static let url = URL(string: "http://test.com")!

    static let data: Data = Test.data(name: "fixture", extension: "jpeg")

    // Test.image size is 640 x 480 pixels
    static var image: PlatformImage {
        Test.image(named: "fixture", extension: "jpeg")
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

    static func save(_ image: PlatformImage) {
        let url = try! FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        print(url)
        let data = ImageEncoders.ImageIO(type: .png, compressionRatio: 1).encode(image)!
        try! data.write(to: url)
    }
}

extension ImageDecodingContext {
    static var mock: ImageDecodingContext {
        mock(data: Test.data)
    }

    static func mock(data: Data) -> ImageDecodingContext {
        ImageDecodingContext(request: Test.request, data: data, isCompleted: true, urlResponse: nil, cacheType: nil)
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

@propertyWrapper final class Atomic<T> {
    private var value: T
    private let lock: os_unfair_lock_t

    init(wrappedValue value: T) {
        self.value = value
        self.lock = .allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
    }

    var wrappedValue: T {
        get { getValue() }
        set { setValue(newValue) }
    }

     private func getValue() -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return value
    }

    private func setValue(_ newValue: T) {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        value = newValue
    }
}
