// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import NukeUI
import SwiftUI
import UIKit

/// Demonstrates the built-in image processors and how to write a custom one.
///
/// ```swift
/// ImageRequest(url: url, processors: [.resize(width: 320), .circle()])
/// ```
struct ImageProcessingDemo: View {
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Self.examples) { example in
                        DemoExample(example.title, caption: example.caption) {
                            LazyImage(request: ImageRequest(url: DemoImages.landscape, processors: example.processors)) { state in
                                if let image = state.image {
                                    image.resizable().scaledToFit()
                                } else {
                                    DemoPlaceholder()
                                }
                            }
                            .frame(height: 110)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .demoInfo(Self.info)
    }

    private static let info = DemoInfo(
        "Image Processing",
        "Processors run on a background queue and the result goes into the memory cache, so the work is done only once. Requests that differ only in their processors still share a single download.",
        code: """
        ImageRequest(url: url, processors: [
            .resize(width: 320),
            .circle()
        ])
        """,
        points: [
            .init("Built in", "Resize, circle, rounded corners, blur, and any Core Image filter."),
            .init("Custom", "Conform to `ImageProcessing`. The `identifier` is what the caches key on, so it has to describe the parameters."),
            .init("Order", "Resize first. Everything after it works on fewer pixels."),
            .init("Caching", "The processed image is what is stored in the memory cache. The original is not kept around.")
        ]
    )

    private struct Example: Identifiable {
        let id: String
        let caption: String
        let processors: [any ImageProcessing]

        var title: String { id }

        init(_ title: String, _ caption: String, _ processors: [any ImageProcessing]) {
            self.id = title
            self.caption = caption
            self.processors = processors
        }
    }

    private static let size = CGSize(width: 160, height: 110)

    private static let examples: [Example] = [
        Example("Original", "No processors", []),
        Example("Resize", ".resize(size:)", [
            .resize(size: size)
        ]),
        Example("Crop", ".resize(size:crop:)", [
            .resize(size: size, contentMode: .aspectFill, crop: true)
        ]),
        Example("Rounded Corners", ".roundedCorners(radius:)", [
            .resize(size: size, crop: true),
            .roundedCorners(radius: 16)
        ]),
        Example("Circle", ".circle(border:)", [
            .resize(size: CGSize(width: 110, height: 110), crop: true),
            .circle(border: .init(color: .systemBlue, width: 2))
        ]),
        Example("Blur", ".gaussianBlur(radius:)", [
            .resize(size: size, crop: true),
            .gaussianBlur(radius: 8)
        ]),
        Example("Core Image", ".coreImageFilter(name:)", [
            .resize(size: size, crop: true),
            .coreImageFilter(name: "CISepiaTone")
        ]),
        Example("Custom", "A custom ImageProcessing type", [
            .resize(size: size, crop: true),
            GrayscaleProcessor()
        ]),
        Example("Anonymous", ".process(id:_:)", [
            .resize(size: size, crop: true),
            .process(id: "com.github.kean.demo.tint") { image in
                UIGraphicsImageRenderer(size: image.size).image { context in
                    image.draw(at: .zero)
                    UIColor(red: 0, green: 0.48, blue: 1, alpha: 0.35).setFill()
                    context.fill(CGRect(origin: .zero, size: image.size))
                }
            }
        ])
    ]
}

/// A custom processor. Implementing ``ImageProcessing`` takes two things: the
/// processing itself, and an identifier that makes the processed image
/// distinct from the original one in the cache.
///
/// Conforming to `Hashable` also gives you a `hashableIdentifier` used by the
/// memory cache, where string comparisons would be too slow.
private struct GrayscaleProcessor: ImageProcessing, Hashable {
    let identifier = "com.github.kean.demo.grayscale"

    func process(_ image: PlatformImage) -> PlatformImage? {
        guard let cgImage = image.cgImage else { return nil }
        guard let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        guard let output = context.makeImage() else { return nil }
        return UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
    }
}
