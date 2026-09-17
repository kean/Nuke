// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import ImageIO
import Nuke

/// What Image I/O reads in a file without decoding it: what it takes the
/// file for, how many images it counts, and the first one's properties.
///
/// It is a second opinion next to the pipeline's. ``AssetType`` names a file
/// from its first bytes, and a decoder takes it or doesn't; Image I/O parses
/// the header. When a decoder refuses a file, or a decode changes it, the
/// header says why.
///
/// Reading it parses the structure of the file, not its pixels, but counting
/// the images of a GIF walks every frame, so ``read(_:)`` does it off the
/// main thread.
struct DemoImageHeader: Sendable {
    /// The type identifier Image I/O takes the file for, e.g. `public.heic`,
    /// or `nil` if it takes it for no image.
    let type: String?
    let imageCount: Int
    let width: Int?
    let height: Int?
    let depth: Int?
    let colorModel: String?
    let profile: String?
    /// The EXIF orientation, 1–8, if the file has one.
    let orientation: Int?

    init(data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            type = nil
            imageCount = 0
            width = nil
            height = nil
            depth = nil
            colorModel = nil
            profile = nil
            orientation = nil
            return
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        type = CGImageSourceGetType(source) as String?
        imageCount = CGImageSourceGetCount(source)
        width = properties[kCGImagePropertyPixelWidth] as? Int
        height = properties[kCGImagePropertyPixelHeight] as? Int
        depth = properties[kCGImagePropertyDepth] as? Int
        colorModel = properties[kCGImagePropertyColorModel] as? String
        profile = properties[kCGImagePropertyProfileName] as? String
        orientation = properties[kCGImagePropertyOrientation] as? Int
    }

    /// Reads the header of the data off the main actor.
    static func read(_ data: Data) async -> DemoImageHeader {
        await Task.detached(priority: .userInitiated) {
            DemoImageHeader(data: data)
        }.value
    }

    /// "public.heic · 1 image", or "not an image type · 0 images".
    var typeSummary: String {
        "\(type ?? "not an image type") · \(imageCount) \(imageCount == 1 ? "image" : "images")"
    }

    /// "1008×756 · 8 bpc · RGB · orientation 6", or `nil` if the header
    /// gives no size.
    var pixelSummary: String? {
        guard let width, let height else { return nil }
        let parts = ["\(width)×\(height)", depth.map { "\($0) bpc" }, colorModel, orientation.map { "orientation \($0)" }]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

extension Optional<AssetType> {
    /// The type as Swift spells it, `.heic`, or `nil`.
    var demoLiteral: String {
        self == nil ? "nil" : "." + demoFormatName
    }
}

/// The name of a value's type without its module, `ImageDecoders.Default`,
/// the way the diagnostics records write it.
func demoTypeName(of value: Any) -> String {
    let name = String(reflecting: type(of: value))
    return demoWithoutModule(name.contains(":") ? demoAfterLastColon(name) : name)
}

/// A type name as a diagnostics record wrote it, with the extension prefix
/// taken off: `ImageDecoders.Video` for
/// `(extension in NukeVideo):Nuke.ImageDecoders.Video`. A type declared in an
/// extension from another module reflects that way, and the records keep all
/// of it. Any other name is returned as it is.
func demoRecordedTypeName(_ name: String) -> String {
    guard name.contains(":") else {
        return name
    }
    return demoWithoutModule(demoAfterLastColon(name))
}

private func demoAfterLastColon(_ name: String) -> String {
    guard let colon = name.lastIndex(of: ":") else {
        return name
    }
    return String(name[name.index(after: colon)...])
}

private func demoWithoutModule(_ name: String) -> String {
    guard let dot = name.firstIndex(of: ".") else {
        return name
    }
    return String(name[name.index(after: dot)...])
}
