// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import CoreGraphics
import Foundation
import Nuke
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// Runs the inputs of the Fixture Zoo through a pipeline, one at a time, and
/// keeps what became of each.
///
/// The pipeline is the zoo's own, made by ``DemoPipelineProbe``: no memory or
/// disk cache, so a run decodes every input again, and the registry every
/// other pipeline uses, `ImageDecoders.Video` included. It records
/// diagnostics, which is where the decoder, the decode and decompression
/// times, and the memory cost come from. Its loader is a
/// ``DemoFixtureLoader``, which answers at once. While the demo's network
/// conditions are on, they apply here too, and an input they lose is
/// ``Outcome/Verdict/notLoaded``, never judged.
///
/// **Crashes.** One input at a time, the zoo writes down which one it is
/// decoding before it starts and crosses it out when it's done (see
/// ``FixtureZooCrashLog``). An app that goes down mid-decode leaves the note
/// behind, and the next launch reads it as a crash of that input. Inputs that
/// crashed are skipped by the next run, so that opening the zoo doesn't take
/// the app down again; each one runs only when it's asked for by itself.
///
/// **Safe and full.** A run decodes every input the way a request with no
/// options does, except the ones with a ``DemoZooInput/safeMaxPixelSize``,
/// which it asks for as a thumbnail. ``Mode/full`` decodes those in full too.
@MainActor @Observable
final class FixtureZooModel {
    /// What became of each input in the last run that reached it.
    private(set) var outcomes: [DemoZooInput: Outcome] = [:]
    /// The inputs the current run has yet to reach.
    private(set) var queue: [DemoZooInput] = []
    /// The input being decoded.
    private(set) var current: DemoZooInput?
    /// The last run that went through every input.
    private(set) var lastRun: Run?

    let crashLog = FixtureZooCrashLog.shared

    /// Made the first time a run asks rather than in `init`, which SwiftUI
    /// runs each time it makes the view, keeping only the first model.
    @ObservationIgnored private lazy var pipeline = makePipeline()
    private var task: Task<Void, Never>?

    /// How to decode the inputs that could take the app down.
    enum Mode: Sendable {
        /// As a thumbnail no larger than their safe size.
        case safe
        /// In full, as a request with no options does.
        case full
    }

    struct Run {
        let mode: Mode
        let duration: Duration
    }

    init() {
        for (input, crash) in crashLog.crashes {
            outcomes[input] = Outcome(crash: crash)
        }
    }

    private func makePipeline() -> ImagePipeline {
        var configuration = ImagePipeline.Configuration(dataLoader: DemoFixtureLoader())
        configuration.imageCache = nil
        configuration.dataCache = nil
        configuration.isDiagnosticsEnabled = true
        return DemoPipelineProbe.makePipeline("Fixture Zoo", configuration: configuration)
    }

    var isRunning: Bool {
        current != nil || !queue.isEmpty
    }

    /// The inputs a run of everything skips: the ones that crashed.
    var skipped: [DemoZooInput] {
        DemoZooInput.allCases.filter { crashLog.crashes[$0] != nil }
    }

    /// Runs every input that hasn't crashed, in the given mode.
    func runAll(mode: Mode = .safe) {
        let inputs = DemoZooInput.allCases.filter { crashLog.crashes[$0] == nil }
        run(inputs, mode: mode, skippedCount: DemoZooInput.allCases.count - inputs.count)
    }

    /// Runs the inputs that have no outcome and didn't crash: every one of
    /// them the first time, and the ones a cancel left out after that.
    func runUnfinished() {
        guard !isRunning else { return }
        let crashed = DemoZooInput.allCases.filter { crashLog.crashes[$0] != nil }
        let inputs = DemoZooInput.allCases.filter { outcomes[$0] == nil && !crashed.contains($0) }
        guard !inputs.isEmpty else { return }
        run(inputs, mode: .safe, skippedCount: crashed.count)
    }

    /// Runs one input, even one that crashed.
    func run(_ input: DemoZooInput, mode: Mode = .safe) {
        crashLog.forget(input)
        run([input], mode: mode, skippedCount: 0)
    }

    /// Runs, in full, every input that is decoded as a thumbnail by default.
    func runRiskyInFull() {
        let inputs = DemoZooInput.allCases.filter { $0.safeMaxPixelSize != nil }
        inputs.forEach(crashLog.forget)
        run(inputs, mode: .full, skippedCount: 0)
    }

    func forgetCrashes() {
        for input in skipped where outcomes[input]?.verdict == .crashed {
            outcomes[input] = nil
        }
        crashLog.forgetAll()
    }

    func cancel() {
        // Kept, so that the next run waits for this one to stop.
        task?.cancel()
        queue = []
        current = nil
    }

    private func run(_ inputs: [DemoZooInput], mode: Mode, skippedCount: Int) {
        let previous = task
        cancel()
        for input in inputs {
            outcomes[input] = nil
        }
        queue = inputs
        let isWholeRun = inputs.count + skippedCount == DemoZooInput.allCases.count
        task = Task {
            // One decode at a time, even across runs, so that the note in the
            // crash log is always the input being decoded.
            await previous?.value
            // Replaced while it waited: the queue is the next run's.
            guard !Task.isCancelled else { return }
            let start = ContinuousClock.now
            while !queue.isEmpty {
                let input = queue.removeFirst()
                current = input
                let outcome = await decode(input, mode: mode)
                guard !Task.isCancelled else { return }
                outcomes[input] = outcome
            }
            current = nil
            if isWholeRun {
                lastRun = Run(mode: mode, duration: start.duration(to: .now))
            }
        }
    }

    // MARK: Decoding

    /// Loads one input and reads what the pipeline made of it. `nil` if the
    /// run was cancelled.
    private func decode(_ input: DemoZooInput, mode: Mode) async -> Outcome? {
        var request = ImageRequest(url: DemoFixture.zoo(input).url)
        var variant = Outcome.Variant.full
        if mode == .safe, let size = input.safeMaxPixelSize {
            request.thumbnail = ImageRequest.ThumbnailOptions(maxPixelSize: size)
            variant = .thumbnail(Int(size))
        }

        crashLog.willDecode(input, variant: variant)
        defer { crashLog.didDecode() }

        let before = DemoFootprint.read()
        let task = pipeline.imageTask(with: request)
        let result: Result<ImageResponse, ImagePipeline.Error>
        do throws(ImagePipeline.Error) {
            result = .success(try await task.response)
        } catch {
            result = .failure(error)
        }
        let after = DemoFootprint.read()
        if case .failure(.cancelled) = result {
            return nil
        }
        var outcome = Outcome(input: input, variant: variant, result: result, metrics: task.metrics)
        // Below a few megabytes, a new high is as likely the screen's own
        // drawing as the decode.
        if let before, let after, after.lifetimePeak > before.lifetimePeak,
           after.lifetimePeak - before.footprint >= 16 << 20 {
            outcome.peakFootprintIncrease = after.lifetimePeak - before.footprint
        }
        outcome.file = await Self.inspect(input)
        return outcome
    }
}

// MARK: - File

extension FixtureZooModel {
    /// Reads the input's header off the main actor: why a decoder refused an
    /// input, or what a decode changed. The data is the fixture store's,
    /// already made for the load.
    fileprivate static func inspect(_ input: DemoZooInput) async -> DemoImageHeader? {
        guard let data = try? await DemoFixtureStore.shared.entry(for: .zoo(input)).data else {
            return nil
        }
        return await DemoImageHeader.read(data)
    }
}

// MARK: - Outcome

extension FixtureZooModel {
    /// What became of an input, read from the response or the error and the
    /// task's record.
    struct Outcome {
        enum Verdict {
            case decoded
            case refused
            /// The data never reached a decoder: the fixture couldn't be
            /// made, or the network conditions lost it.
            case notLoaded
            /// The app went down while the input was decoding.
            case crashed
        }

        enum Variant: Hashable, Codable {
            case full
            case thumbnail(Int)

            var title: String {
                switch self {
                case .full: "full"
                case .thumbnail(let size): "thumbnail \(size) px"
                }
            }
        }

        let verdict: Verdict
        let variant: Variant
        let date: Date

        /// The image and its data, for the preview. `nil` for a bitmap too
        /// large to draw, which is dropped as soon as it has been measured.
        var container: ImageContainer?
        var image: Figures?

        /// The error's case and what it wraps, briefly.
        var error: String?
        var errorDetail: String?

        /// The decoder that decoded the data, or refused it.
        var decoder: String?
        var decodeDuration: TimeInterval?
        var decompressDuration: TimeInterval?
        /// What the task took from start to finish.
        var duration: TimeInterval?
        var byteCount: Int?
        /// How far the app's footprint peaked above where it was when the
        /// input started, if the peak rose past every earlier one by at least
        /// 16 MB. `nil` otherwise, which says only that the input took no
        /// more than something before it did, or not much.
        var peakFootprintIncrease: Int?
        /// What Image I/O reads in the file's header.
        var file: DemoImageHeader?

        /// Why the outcome isn't the one expected, or `nil` if it is or if
        /// nothing is expected of the input.
        private(set) var mismatch: String?

        /// The image, as the pipeline returned it.
        struct Figures {
            /// The size in pixels, with the orientation applied.
            let width: Int
            let height: Int
            /// The size of the bitmap, when the orientation swaps it.
            let bitmapSize: (width: Int, height: Int)?
            let orientation: String?
            let type: String?
            let frameCount: Int
            let delays: [TimeInterval]
            let loopCount: Int?
            /// Whether the container kept the data: the decoder took the
            /// input for an animation.
            let hasData: Bool
            let bitsPerComponent: Int?
            let colorModel: String?
            let memoryCost: Int?

            var isEmpty: Bool { width == 0 || height == 0 }
        }

        init(crash: FixtureZooCrashLog.Crash) {
            verdict = .crashed
            variant = crash.variant
            date = crash.date
            mismatch = "the app went down"
        }

        init(input: DemoZooInput, variant: Variant, result: Result<ImageResponse, ImagePipeline.Error>, metrics: ImageTask.Metrics?) {
            self.variant = variant
            date = Date()
            let stages = metrics?.jobs.flatMap(\.stages) ?? []
            let decode = stages.last { $0.kind == .decode }
            decoder = decode?.decoder.map(demoRecordedTypeName)
            decodeDuration = decode?.workDuration
            decompressDuration = stages.first { $0.kind == .decompress }?.workDuration
            duration = metrics?.duration
            byteCount = (stages.first { $0.kind == .download }?.bytes).map(Int.init)

            switch result {
            case .success(let response):
                verdict = .decoded
                let figures = Figures(response.container, memoryCost: metrics?.image?.memoryCost)
                image = figures
                // A bitmap past this is the one input that could take the
                // app down again, drawn in a tile.
                if max(figures.width, figures.height) <= 8192 {
                    container = response.container
                }
            case .failure(let error):
                verdict = switch error {
                case .dataLoadingFailed, .dataDownloadExceededMaximumSize: .notLoaded
                default: .refused
                }
                self.error = error.demoCaseName
                errorDetail = Self.detail(of: error)
                if case .decodingFailed(let failed, _, _) = error {
                    decoder = demoTypeName(of: failed)
                }
            }
            mismatch = findMismatch(against: input.expectation)
        }

        private func findMismatch(against expectation: DemoZooExpectation) -> String? {
            switch (verdict, expectation.outcome) {
            case (.crashed, _):
                return "the app went down"
            case (.notLoaded, _), (_, .either):
                return nil
            case (.refused, .decoded):
                return "expected it decoded"
            case (.decoded, .refused):
                return "expected it refused"
            case (.refused, .refused):
                return nil
            case (.decoded, .decoded):
                guard let image else { return nil }
                if image.isEmpty {
                    return "an empty image"
                }
                if let size = expectation.size {
                    let (width, height) = expected(size)
                    if image.width != width || image.height != height {
                        return "\(image.width)×\(image.height), expected \(width)×\(height)"
                    }
                }
                if let frames = expectation.frames, frames != image.frameCount {
                    return "\(image.frameCount == 1 ? "a still" : "\(image.frameCount) frames"), expected \(frames == 1 ? "a still" : "\(frames)")"
                }
                if let delays = expectation.delays,
                   delays.count != image.delays.count || zip(delays, image.delays).contains(where: { abs($0 - $1) > 0.0005 }) {
                    return "\(demoDelayList(image.delays)), expected \(demoDelayList(delays))"
                }
                return nil
            }
        }

        /// The expected size, scaled down to a thumbnail's if the input was
        /// decoded as one.
        private func expected(_ size: (width: Int, height: Int)) -> (Int, Int) {
            guard case .thumbnail(let maxSize) = variant, max(size.width, size.height) > maxSize else {
                return size
            }
            let scale = Double(maxSize) / Double(max(size.width, size.height))
            return (Int((Double(size.width) * scale).rounded()), Int((Double(size.height) * scale).rounded()))
        }

        var isUnexpected: Bool {
            mismatch != nil
        }

        // MARK: Errors

        /// What a pipeline error wraps, in a few words.
        private static func detail(of error: ImagePipeline.Error) -> String? {
            switch error {
            case .dataLoadingFailed(let underlying):
                demoLoaderErrorSummary(underlying) ?? String(describing: underlying)
            case let .decodingFailed(decoder, _, underlying):
                underlying is ImageDecodingError
                    ? demoTypeName(of: decoder)
                    : demoLoaderErrorSummary(underlying) ?? String(describing: underlying)
            case .dataIsEmpty:
                "the loader sent no bytes"
            case .decoderNotRegistered:
                "no decoder took the data"
            default:
                nil
            }
        }
    }
}

extension FixtureZooModel.Outcome.Figures {
    init(_ container: ImageContainer, memoryCost: Int?) {
        let image = container.image
        let cgImage = image.cgImage
        let width = Int((image.size.width * image.scale).rounded())
        let height = Int((image.size.height * image.scale).rounded())
        self.width = width
        self.height = height
        if let cgImage, cgImage.width != width || cgImage.height != height {
            bitmapSize = (cgImage.width, cgImage.height)
        } else {
            bitmapSize = nil
        }
        #if canImport(UIKit)
        orientation = image.imageOrientation == .up ? nil : Self.name(of: image.imageOrientation)
        #else
        orientation = nil
        #endif
        type = container.type.map { Self.name(of: $0) }
        frameCount = container.animation?.frameCount ?? 1
        delays = container.animation?.delays ?? []
        loopCount = container.animation?.loopCount
        hasData = container.data != nil
        bitsPerComponent = cgImage?.bitsPerComponent
        colorModel = cgImage?.colorSpace.map { Self.name(of: $0) }
        self.memoryCost = memoryCost
    }

    /// `jpeg` for `public.jpeg`, `heics` for `public.heics`.
    private static func name(of type: AssetType) -> String {
        type.rawValue.split(separator: ".").last.map(String.init) ?? type.rawValue
    }

    private static func name(of space: CGColorSpace) -> String {
        if let name = space.name as String? {
            // "kCGColorSpaceDisplayP3" → "DisplayP3"
            return name.replacingOccurrences(of: "kCGColorSpace", with: "")
        }
        return switch space.model {
        case .monochrome: "Gray"
        case .rgb: "RGB"
        case .cmyk: "CMYK"
        case .indexed: "Indexed"
        default: "model \(space.model.rawValue)"
        }
    }

    #if canImport(UIKit)
    private static func name(of orientation: UIImage.Orientation) -> String {
        switch orientation {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        case .upMirrored: "upMirrored"
        case .downMirrored: "downMirrored"
        case .leftMirrored: "leftMirrored"
        case .rightMirrored: "rightMirrored"
        @unknown default: "orientation \(orientation.rawValue)"
        }
    }
    #endif
}

// MARK: - Crash Log

/// Where the zoo writes down the input it's decoding, and the crashes that
/// left the note behind.
///
/// The note is in `UserDefaults`, synchronized as soon as it's written and
/// again when it's crossed out, so that a crash a moment later can't lose
/// it. The first time the log is used in a launch, a note still there is a
/// crash of that input, dated when its decode started. A crash, a memory
/// termination, and a stop from Xcode in the middle of a decode all look the
/// same from here.
@MainActor @Observable
final class FixtureZooCrashLog {
    static let shared = FixtureZooCrashLog()

    struct Crash: Codable {
        let input: String
        let variant: FixtureZooModel.Outcome.Variant
        /// When the decode started.
        let date: Date
    }

    private(set) var crashes: [DemoZooInput: Crash] = [:]

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let decodingKey = "com.github.kean.NukeDemo.FixtureZoo.decoding"
    private static let crashesKey = "com.github.kean.NukeDemo.FixtureZoo.crashes"

    private init() {
        let saved = defaults.data(forKey: Self.crashesKey)
            .flatMap { try? JSONDecoder().decode([Crash].self, from: $0) } ?? []
        for crash in saved {
            if let input = DemoZooInput(rawValue: crash.input) {
                crashes[input] = crash
            }
        }
        if let data = defaults.data(forKey: Self.decodingKey),
           let crash = try? JSONDecoder().decode(Crash.self, from: data),
           let input = DemoZooInput(rawValue: crash.input) {
            crashes[input] = crash
            defaults.removeObject(forKey: Self.decodingKey)
            save()
        }
    }

    /// Writes down the input about to be decoded, and waits for it to be
    /// stored.
    func willDecode(_ input: DemoZooInput, variant: FixtureZooModel.Outcome.Variant) {
        let crash = Crash(input: input.rawValue, variant: variant, date: Date())
        defaults.set(try? JSONEncoder().encode(crash), forKey: Self.decodingKey)
        defaults.synchronize()
    }

    /// Crosses the input out: its decode is over.
    func didDecode() {
        defaults.removeObject(forKey: Self.decodingKey)
        defaults.synchronize()
    }

    func forget(_ input: DemoZooInput) {
        guard crashes.removeValue(forKey: input) != nil else { return }
        save()
    }

    func forgetAll() {
        crashes.removeAll()
        save()
    }

    private func save() {
        let list = DemoZooInput.allCases.compactMap { crashes[$0] }
        defaults.set(try? JSONEncoder().encode(list), forKey: Self.crashesKey)
        defaults.synchronize()
    }
}
