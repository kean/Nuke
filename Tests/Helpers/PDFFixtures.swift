// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation

/// PDF documents written by hand, and by Quartz.
///
/// A document written by hand says exactly what a test asserts on, including
/// what `CGContext` can't write, such as `/Rotate`. The one Quartz writes is the
/// counterpart: the bytes a real producer makes, encrypted too.
extension Test {
    /// A page of a document made with ``Test/pdf(pages:)``.
    struct PDFPage {
        /// The media box, in points.
        var mediaBox: CGRect
        var cropBox: CGRect?
        /// The value of `/Rotate`, in degrees.
        var rotation: Int?
        /// What the page paints, in the order it's painted, in page coordinates.
        /// Anything else stays unpainted.
        var fills: [(rect: CGRect, color: PixelColor)] = []
    }

    /// A PDF document with the given pages.
    static func pdf(pages: [PDFPage]) -> Data {
        // 1 is the catalog, 2 the page tree, and each page is two objects
        // from there on: the page and its content stream.
        var objects = ["<< /Type /Catalog /Pages 2 0 R >>"]
        let kids = pages.indices.map { "\(3 + $0 * 2) 0 R" }.joined(separator: " ")
        objects.append("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>")
        for (index, page) in pages.enumerated() {
            var entries = ["/Type /Page", "/Parent 2 0 R", "/MediaBox \(pdfArray(page.mediaBox))", "/Contents \(4 + index * 2) 0 R"]
            if let cropBox = page.cropBox {
                entries.append("/CropBox \(pdfArray(cropBox))")
            }
            if let rotation = page.rotation {
                entries.append("/Rotate \(rotation)")
            }
            objects.append("<< \(entries.joined(separator: " ")) >>")

            let content = page.fills.map { rect, color in
                let components = [color.red, color.green, color.blue].map { "\(Double($0) / 255)" }.joined(separator: " ")
                return "\(components) rg \(rect.minX) \(rect.minY) \(rect.width) \(rect.height) re f"
            }.joined(separator: "\n")
            objects.append("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream")
        }

        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            text += String(format: "%010d 00000 n \n", offset)
        }
        text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        return Data(text.utf8)
    }

    private static func pdfArray(_ rect: CGRect) -> String {
        "[\(rect.minX) \(rect.minY) \(rect.maxX) \(rect.maxY)]"
    }

    /// A one-page document written by Quartz, painted solid red.
    ///
    /// - parameter auxiliaryInfo: The dictionary `CGPDFContext` takes, which is
    ///   where the passwords go.
    static func quartzPDF(size: CGSize, auxiliaryInfo: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)
        let consumer = CGDataConsumer(data: data)!
        let context = CGContext(consumer: consumer, mediaBox: &mediaBox, auxiliaryInfo as CFDictionary)!
        context.beginPDFPage(nil)
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
