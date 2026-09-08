// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

/// The pipeline emits the signposts from the stages the diagnostics record,
/// and it emits them only while something is collecting them – which nothing
/// is during a test run. What is worth testing is what goes into them: the
/// name, which has to be the same at both ends of an interval, and the message.
@Suite(.timeLimit(.minutes(1)))
struct SignpostTests {
    typealias Stage = ImagePipeline.Diagnostics.Stage

    // MARK: - Name

    @Test func tracedStagesAreNamed() {
        #expect(name(of: .download) == "LoadImageData")
        #expect(name(of: .decode) == "DecodeImageData")
        #expect(name(of: .process) == "ProcessImage")
        #expect(name(of: .decompress) == "DecompressImage")
    }

    @Test func progressiveStagesGetTheirOwnNames() {
        #expect(name(of: .decode, isProgressive: true) == "DecodeProgressiveImageData")
        #expect(name(of: .process, isProgressive: true) == "ProcessProgressiveImage")
        #expect(name(of: .decompress, isProgressive: true) == "DecompressProgressiveImage")
    }

    /// A progressive download is still one download.
    @Test func downloadIsNamedTheSameEitherWay() {
        #expect(name(of: .download, isProgressive: true) == "LoadImageData")
    }

    @Test func lookupsAndWaitsAreNotTraced() {
        for kind: Stage.Kind in [.memoryLookup, .diskLookup, .rateLimit, .willLoadData, .diskStore, .memoryStore, .unknown] {
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

    @Test func resumedBytesAreOmittedWhenThereAreNone() {
        var stage = makeStage(.download)
        stage.bytes = 1024
        stage.resumedBytes = 0
        #expect(stage.signpostMessage == "1 KB")
    }

    @Test func decodeMessageSaysWhatWasDecoded() {
        var stage = makeStage(.decode)
        stage.decoder = "ImageDecoders.Default"
        stage.format = "jpeg"
        stage.pixels = ImagePipeline.Diagnostics.PixelSize(width: 1350, height: 900)
        #expect(stage.signpostMessage == "ImageDecoders.Default · jpeg 1350×900")
    }

    /// The same words the `ImageTask/Metrics` timeline uses for the row.
    @Test func messageMatchesTheTimelineDetails() {
        var stage = makeStage(.process, isProgressive: true)
        stage.pixels = ImagePipeline.Diagnostics.PixelSize(width: 640, height: 480)
        #expect(stage.signpostMessage == (stage.transferDetails + stage.outputDetails).joined(separator: " · "))
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
