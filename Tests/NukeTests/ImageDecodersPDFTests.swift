// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import CoreGraphics
@testable import Nuke

#if canImport(UIKit)
import UIKit
#endif

private let red = PixelColor(red: 255, green: 0, blue: 0)
private let green = PixelColor(red: 0, green: 255, blue: 0)
private let blue = PixelColor(red: 0, green: 0, blue: 255)
private let yellow = PixelColor(red: 255, green: 255, blue: 0)

/// A 200×100 page with a different color in each quadrant, which tells every
/// rotation and flip apart: red top left, green top right, blue bottom left,
/// and yellow bottom right.
private func quadrants(rotation: Int? = nil) -> Test.PDFPage {
    Test.PDFPage(mediaBox: CGRect(x: 0, y: 0, width: 200, height: 100), rotation: rotation, fills: [
        (CGRect(x: 0, y: 50, width: 100, height: 50), red),
        (CGRect(x: 100, y: 50, width: 100, height: 50), green),
        (CGRect(x: 0, y: 0, width: 100, height: 50), blue),
        (CGRect(x: 100, y: 0, width: 100, height: 50), yellow)
    ])
}

private func solidPage(_ color: PixelColor, size: CGSize = CGSize(width: 100, height: 50)) -> Test.PDFPage {
    Test.PDFPage(mediaBox: CGRect(origin: .zero, size: size), fills: [(CGRect(origin: .zero, size: size), color)])
}

private func request(thumbnail: ImageRequest.ThumbnailOptions? = nil, scale: CGFloat = 1) -> ImageRequest {
    var request = ImageRequest(url: Test.url)
    request.thumbnail = thumbnail
    request.scale = scale
    return request
}

/// The colors at the center of each quadrant of the image, clockwise from the
/// top left.
private func cornerColors(of image: PlatformImage) throws -> [PixelColor] {
    let bitmap = try #require(RGBABitmap(image: image))
    let (left, right) = (bitmap.width / 4, bitmap.width * 3 / 4)
    let (top, bottom) = (bitmap.height / 4, bitmap.height * 3 / 4)
    return [
        bitmap.color(atX: left, y: top),
        bitmap.color(atX: right, y: top),
        bitmap.color(atX: right, y: bottom),
        bitmap.color(atX: left, y: bottom)
    ]
}

private func expectColors(_ colors: [PixelColor], _ expected: [PixelColor], sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(colors.count == expected.count, sourceLocation: sourceLocation)
    for (color, other) in zip(colors, expected) {
        #expect(color.isClose(to: other), "\(colors) is not \(expected)", sourceLocation: sourceLocation)
    }
}

/// Without the decoder, a document is what it has always been.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelinePDFWithoutDecoderTests {
    @Test func theDocumentDoesNotLoad() async throws {
        let dataLoader = MockDataLoader()
        let data = Test.pdf(pages: [quadrants()])
        dataLoader.results[Test.url] = .success((data, URLResponse(url: Test.url, mimeType: "application/pdf", expectedContentLength: data.count, textEncodingName: nil)))
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            let registry = ImageDecoderRegistry()
            $0.makeImageDecoder = { registry.decoder(for: $0) }
        }

        do {
            let response = try await pipeline.imageTask(with: Test.url).response
#if os(macOS)
            // `NSImage(data:)` reads PDF documents, which predates the decoder.
            #expect(response.container.type == .pdf)
#else
            Issue.record("Expected a failure, got \(response)")
#endif
        } catch {
            guard case .decodingFailed = error else {
                Issue.record("Expected decodingFailed, got \(error)")
                return
            }
        }
    }

    @Test func aThumbnailStopsAtTheSizeOfThePage() async throws {
        // A thumbnail goes through Image I/O, which draws a page, and which
        // treats it like any other image.
        let dataLoader = MockDataLoader()
        let data = Test.pdf(pages: [quadrants()])
        dataLoader.results[Test.url] = .success((data, URLResponse(url: Test.url, mimeType: "application/pdf", expectedContentLength: data.count, textEncodingName: nil)))
        let pipeline = ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            let registry = ImageDecoderRegistry()
            $0.makeImageDecoder = { registry.decoder(for: $0) }
        }

        let response = try await pipeline.imageTask(with: request(thumbnail: ImageRequest.ThumbnailOptions(maxPixelSize: 400))).response
        #expect(response.image.cgImage?.width == 200)
        #expect(response.image.cgImage?.height == 100)
    }
}

#if !os(tvOS)

private func decode(_ data: Data, request: ImageRequest = ImageRequest(url: Test.url), configure: (inout ImageDecoders.PDF) -> Void = { _ in }) throws -> ImageContainer {
    var decoder = try #require(ImageDecoders.PDF(context: ImageDecodingContext(request: request, data: data)))
    configure(&decoder)
    return try decoder.decode(data)
}

@Suite(.timeLimit(.minutes(5)))
struct ImageDecodersPDFTests {
    // MARK: - Matching

    @Test func initReturnsNilForAnotherFormat() {
        let context = ImageDecodingContext(request: Test.request, data: Test.data)
        #expect(ImageDecoders.PDF(context: context) == nil)
    }

    @Test func initMatchesPartialData() {
        // The decoder made for the first chunk is the one that gets the last.
        let data = Test.pdf(pages: [quadrants()]).prefix(32)
        let context = ImageDecodingContext(request: Test.request, data: data, isCompleted: false)
        #expect(ImageDecoders.PDF(context: context) != nil)
    }

    @Test func noPreviewsFromPartialData() throws {
        let data = Test.pdf(pages: [quadrants()])
        let context = ImageDecodingContext(request: Test.request, data: data, isCompleted: false)
        let decoder = try #require(ImageDecoders.PDF(context: context))
        #expect(decoder.decodePartiallyDownloadedData(data) == nil)
    }

    // MARK: - Decoding

    @Test func decodesAtOnePixelPerPoint() throws {
        let container = try decode(Test.pdf(pages: [quadrants()]))

        #expect(container.type == .pdf)
        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 200)
        #expect(cgImage.height == 100)
        #expect(container.image.size == CGSize(width: 200, height: 100))
    }

    @Test func pixelsAreNotFlipped() throws {
        let container = try decode(Test.pdf(pages: [quadrants()]))
        expectColors(try cornerColors(of: container.image), [red, green, yellow, blue])
    }

    @Test func dataIsNotAttached() throws {
        let container = try decode(Test.pdf(pages: [quadrants()]))
        #expect(container.data == nil)
        #expect(container.animation == nil)
    }

    @Test func decodesDocumentWrittenByQuartz() throws {
        let data = Test.quartzPDF(size: CGSize(width: 120, height: 80))
        let container = try decode(data)

        #expect(container.type == .pdf)
        expectColors(try cornerColors(of: container.image), [red, red, red, red])
    }

    @Test(arguments: [2.0, 3.0] as [CGFloat])
    func scaleOfTheRequestMultipliesThePixels(scale: CGFloat) throws {
        let container = try decode(Test.pdf(pages: [quadrants()]), request: request(scale: scale))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == Int(200 * scale))
        #expect(cgImage.height == Int(100 * scale))
        // The image is displayed at the size of the page
        #expect(container.image.size == CGSize(width: 200, height: 100))
#if canImport(UIKit)
        #expect(container.image.scale == scale)
#endif
    }

    @Test func unpaintedPartsOfThePageStayTransparent() throws {
        let page = Test.PDFPage(mediaBox: CGRect(x: 0, y: 0, width: 100, height: 100), fills: [
            (CGRect(x: 0, y: 0, width: 50, height: 100), red)
        ])
        let container = try decode(Test.pdf(pages: [page]))

        let bitmap = try #require(RGBABitmap(image: container.image))
        #expect(bitmap.alpha(atX: 25, y: 50) == 255)
        #expect(bitmap.alpha(atX: 75, y: 50) == 0)
    }

    // MARK: - Rotation

    @Test func rotation90() throws {
        let container = try decode(Test.pdf(pages: [quadrants(rotation: 90)]))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 200)
        // Clockwise, so the top left corner is what was the bottom left
        expectColors(try cornerColors(of: container.image), [blue, red, green, yellow])
    }

    @Test func rotation180() throws {
        let container = try decode(Test.pdf(pages: [quadrants(rotation: 180)]))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 200)
        #expect(cgImage.height == 100)
        expectColors(try cornerColors(of: container.image), [yellow, blue, red, green])
    }

    @Test(arguments: [270, -90])
    func rotation270(rotation: Int) throws {
        let container = try decode(Test.pdf(pages: [quadrants(rotation: rotation)]))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 200)
        expectColors(try cornerColors(of: container.image), [green, yellow, blue, red])
    }

    // MARK: - Crop Box

    @Test func cropBoxWithAnOriginSelectsThePixels() throws {
        // Only the blue quadrant and a part of the yellow one.
        var page = quadrants()
        page.cropBox = CGRect(x: 50, y: 10, width: 100, height: 30)
        let container = try decode(Test.pdf(pages: [page]))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 30)
        expectColors(try cornerColors(of: container.image), [blue, yellow, yellow, blue])
    }

    @Test func cropBoxOfARotatedPage() throws {
        var page = quadrants(rotation: 90)
        page.cropBox = CGRect(x: 50, y: 10, width: 100, height: 30)
        let container = try decode(Test.pdf(pages: [page]))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 30)
        #expect(cgImage.height == 100)
        // A clockwise quarter turn puts the blue side on top
        expectColors(try cornerColors(of: container.image), [blue, blue, yellow, yellow])
    }

    @Test func mediaBoxWithAnOrigin() throws {
        let page = Test.PDFPage(mediaBox: CGRect(x: 1000, y: 2000, width: 100, height: 50), fills: [
            (CGRect(x: 1000, y: 2000, width: 50, height: 50), red),
            (CGRect(x: 1050, y: 2000, width: 50, height: 50), green)
        ])
        let container = try decode(Test.pdf(pages: [page]))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 50)
        expectColors(try cornerColors(of: container.image), [red, green, green, red])
    }

    // MARK: - Pages

    @Test func firstPageByDefault() throws {
        let data = Test.pdf(pages: [solidPage(red), solidPage(green)])
        expectColors(try cornerColors(of: try decode(data).image), [red, red, red, red])
    }

    @Test func pageIndexSelectsThePage() throws {
        let data = Test.pdf(pages: [solidPage(red), solidPage(green, size: CGSize(width: 40, height: 80)), solidPage(blue)])

        let container = try decode(data) { $0.pageIndex = 1 }

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 40)
        #expect(cgImage.height == 80)
        expectColors(try cornerColors(of: container.image), [green, green, green, green])
    }

    @Test(arguments: [2, -1, Int.max, Int.min])
    func pageOutOfRangeThrows(index: Int) {
        let data = Test.pdf(pages: [solidPage(red), solidPage(green)])
        #expect(throws: ImageDecodingError.self) {
            _ = try decode(data) { $0.pageIndex = index }
        }
    }

    // MARK: - Invalid Documents

    @Test func corruptDocumentThrows() {
        let data = Data("%PDF-1.7\nThis is not a document".utf8)
        #expect(throws: ImageDecodingError.self) {
            _ = try decode(data)
        }
    }

    @Test func documentWithNoPagesThrows() {
        #expect(throws: ImageDecodingError.self) {
            _ = try decode(Test.pdf(pages: []))
        }
    }

    @Test(arguments: 2...8)
    func truncatedDocumentThrows(divisor: Int) {
        let data = Test.quartzPDF(size: CGSize(width: 100, height: 100))
        #expect(throws: ImageDecodingError.self) {
            _ = try decode(data.prefix(data.count / divisor))
        }
    }

    @Test func documentThatNeedsAPasswordThrows() {
        let data = Test.quartzPDF(size: CGSize(width: 100, height: 100), auxiliaryInfo: [
            kCGPDFContextUserPassword: "user",
            kCGPDFContextOwnerPassword: "owner"
        ])
        #expect(throws: ImageDecodingError.self) {
            _ = try decode(data)
        }
    }

    @Test func documentWithOnlyAnOwnerPasswordDecodes() throws {
        // Anyone can open it: the password guards printing and copying.
        let data = Test.quartzPDF(size: CGSize(width: 100, height: 100), auxiliaryInfo: [
            kCGPDFContextUserPassword: "",
            kCGPDFContextOwnerPassword: "owner"
        ])
        expectColors(try cornerColors(of: try decode(data).image), [red, red, red, red])
    }

    @Test func zeroSizedPageThrows() {
        let data = Test.pdf(pages: [Test.PDFPage(mediaBox: .zero)])
        #expect(throws: ImageDecodingError.self) {
            _ = try decode(data)
        }
    }

    @Test func tinyPageGetsAtLeastAPixel() throws {
        let page = solidPage(red, size: CGSize(width: 0.25, height: 0.25))
        let container = try decode(Test.pdf(pages: [page]))
        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width >= 1)
        #expect(cgImage.height >= 1)
    }

    @Test(arguments: [0, -1, .nan, .infinity] as [CGFloat])
    func invalidScaleDoesNotCrash(scale: CGFloat) {
        _ = try? decode(Test.pdf(pages: [quadrants()]), request: request(scale: scale))
    }

    // MARK: - Memory

    @Test func defaultCapBoundsALargePage() throws {
        // The largest page Acrobat allows, which would be 3.7 GB in pixels.
        let page = solidPage(red, size: CGSize(width: 14_400, height: 7_200))
        let container = try decode(Test.pdf(pages: [page]), request: request(scale: 3))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 4096)
        #expect(cgImage.height == 2048)
        #expect(cgImage.bytesPerRow * cgImage.height <= 64 * 1024 * 1024)
    }

    @Test func maxPixelSizeCanBeChanged() throws {
        let container = try decode(Test.pdf(pages: [quadrants()])) { $0.maxPixelSize = 50 }

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 50)
        #expect(cgImage.height == 25)
        expectColors(try cornerColors(of: container.image), [red, green, yellow, blue])
    }

    @Test func capAppliesToAThumbnail() throws {
        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100_000)
        let container = try decode(Test.pdf(pages: [quadrants()]), request: request(thumbnail: thumbnail))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 4096)
        #expect(cgImage.height == 2048)
    }

    // MARK: - Thumbnails

    @Test func thumbnailWithMaxPixelSize() throws {
        let page = solidPage(red, size: CGSize(width: 612, height: 792))
        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 100)
        let container = try decode(Test.pdf(pages: [page]), request: request(thumbnail: thumbnail))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 77)
        #expect(cgImage.height == 100)
        #expect(container.type == .pdf)
    }

    @Test func thumbnailIsLargerThanThePage() throws {
        // A page has no pixels to run out of: unlike with a raster image,
        // asking for more than the page gets a sharp image of that size.
        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let container = try decode(Test.pdf(pages: [quadrants()]), request: request(thumbnail: thumbnail))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 400)
        #expect(cgImage.height == 200)
        expectColors(try cornerColors(of: container.image), [red, green, yellow, blue])
    }

    @Test func thumbnailOfARotatedPage() throws {
        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let container = try decode(Test.pdf(pages: [quadrants(rotation: 90)]), request: request(thumbnail: thumbnail))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 200)
        #expect(cgImage.height == 400)
        expectColors(try cornerColors(of: container.image), [blue, red, green, yellow])
    }

    @Test func thumbnailWithAspectFit() throws {
        let thumbnail = ImageRequest.ThumbnailOptions(size: CGSize(width: 100, height: 100), unit: .pixels, contentMode: .aspectFit)
        let container = try decode(Test.pdf(pages: [quadrants()]), request: request(thumbnail: thumbnail))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 50)
    }

    @Test func thumbnailWithAspectFill() throws {
        let thumbnail = ImageRequest.ThumbnailOptions(size: CGSize(width: 100, height: 100), unit: .pixels, contentMode: .aspectFill)
        let container = try decode(Test.pdf(pages: [quadrants()]), request: request(thumbnail: thumbnail))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 200)
        #expect(cgImage.height == 100)
    }

    @Test func thumbnailOfALargePageIsDrawnAtItsOwnSize() throws {
        // Drawing the page at its full size first would take 829 MB.
        let page = solidPage(red, size: CGSize(width: 14_400, height: 14_400))
        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 64)
        let container = try decode(Test.pdf(pages: [page]), request: request(thumbnail: thumbnail))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 64)
        #expect(cgImage.height == 64)
    }

    @Test func thumbnailKeepsTheScaleOfTheRequest() throws {
        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 300)
        let container = try decode(Test.pdf(pages: [quadrants()]), request: request(thumbnail: thumbnail, scale: 3))

        let cgImage = try #require(container.image.cgImage)
        #expect(cgImage.width == 300)
        #expect(cgImage.height == 150)
        #expect(container.image.size == CGSize(width: 100, height: 50))
    }
}

/// The decoder through a real pipeline, registered the way an app does it.
@Suite(.timeLimit(.minutes(5)))
struct ImagePipelinePDFTests {
    let dataLoader = MockDataLoader()
    let dataCache = MockDataCache()
    let registry = ImageDecoderRegistry()

    init() {
        registry.register(ImageDecoders.PDF.init)
    }

    private func makePipeline(_ configure: (inout ImagePipeline.Configuration) -> Void = { _ in }) -> ImagePipeline {
        ImagePipeline {
            $0.dataLoader = dataLoader
            $0.imageCache = nil
            $0.makeImageDecoder = { [registry] in registry.decoder(for: $0) }
            configure(&$0)
        }
    }

    private func respond(with data: Data, url: URL = Test.url) {
        dataLoader.results[url] = .success((data, URLResponse(url: url, mimeType: "application/pdf", expectedContentLength: data.count, textEncodingName: nil)))
    }

    @Test func loadsARotatedPage() async throws {
        respond(with: Test.pdf(pages: [quadrants(rotation: 90)]))

        let response = try await makePipeline().imageTask(with: Test.url).response

        let cgImage = try #require(response.image.cgImage)
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 200)
        #expect(response.container.type == .pdf)
        expectColors(try cornerColors(of: response.image), [blue, red, green, yellow])
    }

    @Test func loadsAtTheScaleOfTheRequest() async throws {
        respond(with: Test.pdf(pages: [quadrants()]))

        let response = try await makePipeline().imageTask(with: request(scale: 3)).response

        let cgImage = try #require(response.image.cgImage)
        #expect(cgImage.width == 600)
        #expect(cgImage.height == 300)
        #expect(response.image.size == CGSize(width: 200, height: 100))
        expectColors(try cornerColors(of: response.image), [red, green, yellow, blue])
    }

    @Test func loadsAThumbnail() async throws {
        respond(with: Test.pdf(pages: [solidPage(red, size: CGSize(width: 14_400, height: 7_200))]))

        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 128)
        let response = try await makePipeline().imageTask(with: request(thumbnail: thumbnail)).response

        let cgImage = try #require(response.image.cgImage)
        #expect(cgImage.width == 128)
        #expect(cgImage.height == 64)
        expectColors(try cornerColors(of: response.image), [red, red, red, red])
    }

    @Test func aProcessorRunsOnThePage() async throws {
        respond(with: Test.pdf(pages: [quadrants()]))

        let request = ImageRequest(url: Test.url, processors: [.resize(size: CGSize(width: 100, height: 50), unit: .pixels)])
        let response = try await makePipeline().imageTask(with: request).response

        let cgImage = try #require(response.image.cgImage)
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 50)
        expectColors(try cornerColors(of: response.image), [red, green, yellow, blue])
    }

    @Test func otherImagesKeepTheDefaultDecoder() async throws {
        let response = try await makePipeline().imageTask(with: Test.url).response
        #expect(response.container.type == .jpeg)
    }

    @Test func noPreviewsWithProgressiveDecoding() async throws {
        respond(with: Test.pdf(pages: [quadrants()]))
        let pipeline = makePipeline {
            $0.isProgressiveDecodingEnabled = true
            $0.progressiveDecodingInterval = 0
        }

        let task = pipeline.imageTask(with: Test.url)
        var previews = 0
        for await event in task.events {
            if case .preview = event {
                previews += 1
            }
        }

        let response = try await task.response
        #expect(previews == 0)
        #expect(response.container.type == .pdf)
        #expect(response.image.cgImage?.width == 200)
    }

    // MARK: - Caching

    @Test func theDocumentIsStoredAndDrawnAgain() async throws {
        let data = Test.pdf(pages: [quadrants()])
        respond(with: data)
        let pipeline = makePipeline { $0.dataCache = dataCache }

        _ = try await pipeline.imageTask(with: Test.url).response
        let key = pipeline.cache.makeDataCacheKey(for: Test.request)

        #expect(dataCache.store == [key: data])

        let response = try await pipeline.imageTask(with: Test.url).response
        #expect(dataLoader.createdTaskCount == 1)
        #expect(response.cacheType == .disk)
        #expect(response.container.type == .pdf)
    }

    @Test func aThumbnailIsDrawnFromTheStoredDocument() async throws {
        let data = Test.pdf(pages: [quadrants()])
        respond(with: data)
        let pipeline = makePipeline { $0.dataCache = dataCache }
        _ = try await pipeline.imageTask(with: Test.url).response

        let thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: 400)
        let response = try await pipeline.imageTask(with: request(thumbnail: thumbnail)).response

        #expect(dataLoader.createdTaskCount == 1)
        // Larger than the page: it had to come from the document
        #expect(response.image.cgImage?.width == 400)
    }

    @Test func storeEncodedImagesStoresTheImageUnderItsOwnKey() async throws {
        respond(with: Test.pdf(pages: [quadrants()]))
        let pipeline = makePipeline {
            $0.dataCache = dataCache
            $0.dataCachePolicy = .storeEncodedImages
        }

        _ = try await pipeline.imageTask(with: Test.url).response
        await pipeline.configuration.imageEncodingQueue.waitUntilAllOperationsAreFinished()

        let key = pipeline.cache.makeDataCacheKey(for: Test.request)
        #expect(Array(dataCache.store.keys) == [key])
        #expect(AssetType(try #require(dataCache.store[key])) == .png)

        // What comes back is the drawing, and the default decoder reads it.
        let response = try await pipeline.imageTask(with: Test.url).response
        #expect(dataLoader.createdTaskCount == 1)
        #expect(response.cacheType == .disk)
        #expect(response.container.type == .png)
        expectColors(try cornerColors(of: response.image), [red, green, yellow, blue])
    }

    @Test func pagesWithTheirOwnImageIDDoNotShareAnEntry() async throws {
        respond(with: Test.pdf(pages: [solidPage(red), solidPage(green)]))
        let pipeline = makePipeline {
            $0.imageCache = ImageCache()
            $0.makeImageDecoder = { context in
                var decoder = ImageDecoders.PDF(context: context)
                decoder?.pageIndex = context.request.userInfo["pageIndex"] as? Int ?? 0
                return decoder ?? ImageDecoders.Default(context: context)
            }
        }

        var images: [PlatformImage] = []
        for pageIndex in [0, 1] {
            var request = ImageRequest(url: Test.url)
            request.userInfo["pageIndex"] = pageIndex
            request.imageID = "\(Test.url.absoluteString)#page=\(pageIndex + 1)"
            images.append(try await pipeline.imageTask(with: request).response.image)
        }

        expectColors(try cornerColors(of: images[0]), [red, red, red, red])
        expectColors(try cornerColors(of: images[1]), [green, green, green, green])
    }

    // MARK: - Cancellation

    @Test func cancellingWhileDrawingDoesNotCrash() async throws {
        // About 100 ms to draw, so the cancellation lands in the middle of it.
        let fills = (0..<2_000).map { index -> (rect: CGRect, color: PixelColor) in
            (CGRect(x: index, y: index / 2, width: 2_000, height: 1_000), index % 2 == 0 ? red : blue)
        }
        let page = Test.PDFPage(mediaBox: CGRect(x: 0, y: 0, width: 2_000, height: 1_000), fills: fills)
        respond(with: Test.pdf(pages: [page]))

        let (started, continuation) = AsyncStream.makeStream(of: Void.self)
        let pipeline = makePipeline {
            $0.makeImageDecoder = { context in
                guard let decoder = ImageDecoders.PDF(context: context) else {
                    continuation.yield() // The load fails, which is what the test reports
                    return nil
                }
                return DecoderReportingStart(decoder: decoder) { continuation.yield() }
            }
        }

        var iterator = started.makeAsyncIterator()
        for _ in 0..<5 {
            let task = pipeline.imageTask(with: Test.url)
            await iterator.next()
            task.cancel()
            do {
                _ = try await task.response
                Issue.record("Expected a cancellation")
            } catch {
                guard case .cancelled = error else {
                    Issue.record("Expected cancelled, got \(error)")
                    continue
                }
            }
        }

        // The pipeline still works
        let response = try await pipeline.imageTask(with: Test.url).response
        #expect(response.image.cgImage?.width == 2_000)
    }
}

/// Says when the pipeline has called the decoder, on the decoding queue.
private struct DecoderReportingStart: ImageDecoding {
    let decoder: ImageDecoders.PDF
    let onStart: @Sendable () -> Void

    func decode(_ data: Data) throws -> ImageContainer {
        onStart()
        return try decoder.decode(data)
    }
}

#endif
