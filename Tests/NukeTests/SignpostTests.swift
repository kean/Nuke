// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// The pipeline emits the signposts from the stages the diagnostics record,
/// and only while something is collecting them – which nothing is during a
/// test run. What is worth testing is what goes into them: the name, which has
/// to be the same at both ends of an interval, and the message.
@Suite(.timeLimit(.minutes(1)))
struct SignpostTests {
    typealias Stage = ImagePipeline.Diagnostics.Stage

    // MARK: - Name

    @Test func aTracedStageIsNamedAfterItsKind() {
        for kind: Stage.Kind in [.diskLookup, .willLoadData, .download, .diskStore, .decode, .process, .decompress] {
            #expect(name(of: kind) == kind.rawValue)
        }
    }

    @Test func previewsAreCountedApartFromImages() {
        #expect(name(of: .decode, isProgressive: true) == "decodePreview")
        #expect(name(of: .process, isProgressive: true) == "processPreview")
        #expect(name(of: .decompress, isProgressive: true) == "decompressPreview")
    }

    /// A progressive download is still one download.
    @Test func downloadIsNamedTheSameEitherWay() {
        #expect(name(of: .download, isProgressive: true) == "download")
    }

    /// The interval would cost more than the work it measures.
    @Test func theMemoryCacheAndTheRateLimiterAreNotTraced() {
        for kind: Stage.Kind in [.memoryLookup, .memoryStore, .rateLimit, .unknown] {
            #expect(makeStage(kind).signpostName == nil, "\(kind) is not traced")
        }
    }

    // MARK: - Message

    @Test func downloadMessageSaysWhereTheBytesCameFrom() {
        var stage = makeStage(.download)
        stage.source = .network
        stage.bytes = 325_000
        stage.statusCode = 200
        #expect(stage.signpostMessage == "network · 325 KB · HTTP 200")
    }

    @Test func downloadMessageSaysWhatWasResumed() {
        var stage = makeStage(.download)
        stage.source = .network
        stage.bytes = 325_000
        stage.resumedBytes = 25_000
        #expect(stage.signpostMessage == "network · 325 KB (25 KB resumed)")
    }

    @Test func lookupMessageSaysWhatItFound() {
        var stage = makeStage(.diskLookup)
        stage.result = .hit
        stage.bytes = 23_000
        #expect(stage.signpostMessage == "hit · 23 KB")
    }

    @Test func decodeMessageSaysWhatWasDecoded() {
        var stage = makeStage(.decode)
        stage.decoder = "ImageDecoders.Default"
        stage.format = "jpeg"
        stage.pixels = ImagePipeline.Diagnostics.PixelSize(width: 1350, height: 900)
        #expect(stage.signpostMessage == "ImageDecoders.Default · jpeg 1350×900")
    }

    /// The same words, in the same order, as the row of the stage in the
    /// `ImageTask/Metrics` timeline.
    @Test func messageMatchesTheTimelineDetails() {
        var stage = makeStage(.process, isProgressive: true)
        stage.pixels = ImagePipeline.Diagnostics.PixelSize(width: 640, height: 480)
        #expect(stage.signpostMessage == stage.details.joined(separator: " · "))
        #expect(stage.signpostMessage == "preview · 640×480")
    }

    @Test func messageIsEmptyWhenTheStageProducedNothing() {
        #expect(makeStage(.decompress).signpostMessage == "")
    }

    // MARK: - Formatter

    @Test func byteFormatter() {
        #expect(!Formatter.bytes(0).isEmpty)
        #expect(!Formatter.bytes(1024).isEmpty)
        #expect(Formatter.bytes(Int64(2048)) == Formatter.bytes(2048))
    }

    @Test func millisecondFormatter() {
        #expect(Formatter.milliseconds(0.0421) == "42.1 ms")
        #expect(Formatter.milliseconds(0.00001) == "<0.1 ms")
    }

    // MARK: - Helpers

    private func makeStage(_ kind: Stage.Kind, isProgressive: Bool? = nil) -> Stage {
        var stage = Stage(kind: kind, queuedAt: nil, startedAt: nil)
        stage.isProgressive = isProgressive
        return stage
    }

    private func name(of kind: Stage.Kind, isProgressive: Bool = false) -> String? {
        makeStage(kind, isProgressive: isProgressive).signpostName?.description
    }
}
