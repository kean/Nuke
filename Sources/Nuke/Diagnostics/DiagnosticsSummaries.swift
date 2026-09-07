// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Foundation

// The `Codable` summaries the records carry, and the names they print. Every
// one of them is a plain conversion from a type the pipeline uses to the
// value the schema defines.

extension ImageTask.Metrics.RequestSummary {
    init(_ request: ImageRequest) {
        self.url = request.url?.absoluteString
        self.imageID = request.imageID
        self.processors = request.processors.map(\.identifier)
        self.thumbnail = request.thumbnail?.identifier
        self.options = request.options.diagnosticsNames
        self.priority = request.priority
    }
}

extension ImageTask.Metrics.ImageSummary {
    init(_ container: ImageContainer) {
        let pixels = container.image.diagnosticsPixelSize
        self.width = pixels?.width ?? 0
        self.height = pixels?.height ?? 0
        self.format = container.type?.diagnosticsName
        self.isAnimated = container.animation != nil
    }
}

// MARK: - Errors

extension ImagePipeline.Diagnostics.ErrorSummary {
    init(_ error: ImagePipeline.Error) {
        let underlying: (any Swift.Error)? = switch error {
        case .dataLoadingFailed(let error), .decodingFailed(_, _, let error), .processingFailed(_, _, let error): error
        default: nil
        }
        let nsError = underlying.map { $0 as NSError }
        self.init(code: error.diagnosticsCode, description: error.description, underlyingDomain: nsError?.domain, underlyingCode: nsError?.code)
    }
}

extension ImagePipeline.Error {
    /// The name of the case, such as `"dataLoadingFailed"`.
    fileprivate var diagnosticsCode: String {
        switch self {
        case .dataMissingInCache: "dataMissingInCache"
        case .dataLoadingFailed: "dataLoadingFailed"
        case .dataIsEmpty: "dataIsEmpty"
        case .decoderNotRegistered: "decoderNotRegistered"
        case .decodingFailed: "decodingFailed"
        case .processingFailed: "processingFailed"
        case .imageRequestMissing: "imageRequestMissing"
        case .pipelineInvalidated: "pipelineInvalidated"
        case .dataDownloadExceededMaximumSize: "dataDownloadExceededMaximumSize"
        case .cancelled: "cancelled"
        }
    }
}

// MARK: - URLSession

extension ImagePipeline.Diagnostics.URLSessionMetrics {
    init(_ metrics: URLSessionTaskMetrics, urlSessionTaskID: Int) {
        self.urlSessionTaskID = urlSessionTaskID
        self.startedAt = metrics.taskInterval.start.timeIntervalSince1970
        self.endedAt = metrics.taskInterval.end.timeIntervalSince1970
        self.redirectCount = metrics.redirectCount
        self.transactions = metrics.transactionMetrics.map(Transaction.init)
    }
}

extension ImagePipeline.Diagnostics.URLSessionMetrics.Transaction {
    init(_ metrics: URLSessionTaskTransactionMetrics) {
        self.url = metrics.request.url?.absoluteString
        self.statusCode = (metrics.response as? HTTPURLResponse)?.statusCode
        self.fetchType = ImagePipeline.Diagnostics.URLSessionMetrics.FetchType(metrics.resourceFetchType)
        self.networkProtocol = metrics.networkProtocolName
        self.tlsVersion = metrics.negotiatedTLSProtocolVersion.map { Self.tlsVersionName($0.rawValue) }
        self.remoteAddress = metrics.remoteAddress
        self.isReusedConnection = metrics.isReusedConnection
        self.isProxyConnection = metrics.isProxyConnection
        self.isCellular = metrics.isCellular
        self.isExpensive = metrics.isExpensive
        self.isConstrained = metrics.isConstrained
        self.requestBytes = metrics.countOfRequestHeaderBytesSent + metrics.countOfRequestBodyBytesSent
        self.responseBytes = metrics.countOfResponseHeaderBytesReceived + metrics.countOfResponseBodyBytesReceived
        self.fetchStartedAt = metrics.fetchStartDate?.timeIntervalSince1970
        self.domainLookupStartedAt = metrics.domainLookupStartDate?.timeIntervalSince1970
        self.domainLookupEndedAt = metrics.domainLookupEndDate?.timeIntervalSince1970
        self.connectStartedAt = metrics.connectStartDate?.timeIntervalSince1970
        self.secureConnectionStartedAt = metrics.secureConnectionStartDate?.timeIntervalSince1970
        self.secureConnectionEndedAt = metrics.secureConnectionEndDate?.timeIntervalSince1970
        self.connectEndedAt = metrics.connectEndDate?.timeIntervalSince1970
        self.requestStartedAt = metrics.requestStartDate?.timeIntervalSince1970
        self.requestEndedAt = metrics.requestEndDate?.timeIntervalSince1970
        self.responseStartedAt = metrics.responseStartDate?.timeIntervalSince1970
        self.responseEndedAt = metrics.responseEndDate?.timeIntervalSince1970
    }

    /// `"TLS 1.3"` for the `tls_protocol_version_t` the connection
    /// negotiated, which is the version as it appears on the wire.
    private static func tlsVersionName(_ version: UInt16) -> String {
        switch version {
        case 0x0301: "TLS 1.0"
        case 0x0302: "TLS 1.1"
        case 0x0303: "TLS 1.2"
        case 0x0304: "TLS 1.3"
        case 0xFEFF: "DTLS 1.0"
        case 0xFEFD: "DTLS 1.2"
        default: String(format: "TLS 0x%04X", version)
        }
    }
}

extension ImagePipeline.Diagnostics.URLSessionMetrics.FetchType {
    init(_ type: URLSessionTaskMetrics.ResourceFetchType) {
        self = switch type {
        case .networkLoad: .networkLoad
        case .localCache: .localCache
        case .serverPush: .serverPush
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }
}

// MARK: - Names

extension ImageRequest.Options {
    private static let diagnosticsNames: [(ImageRequest.Options, String)] = [
        (.disableMemoryCacheReads, "disableMemoryCacheReads"),
        (.disableMemoryCacheWrites, "disableMemoryCacheWrites"),
        (.disableDiskCacheReads, "disableDiskCacheReads"),
        (.disableDiskCacheWrites, "disableDiskCacheWrites"),
        (.returnCacheDataDontLoad, "returnCacheDataDontLoad"),
        (.skipDecompression, "skipDecompression"),
        (.skipDataLoadingQueue, "skipDataLoadingQueue")
    ]

    var diagnosticsNames: [String] {
        guard !isEmpty else { return [] }
        return Self.diagnosticsNames.filter { contains($0.0) }.map(\.1)
    }
}

extension AssetType {
    /// A short name for the records, such as `"jpeg"`.
    var diagnosticsName: String {
        switch self {
        case .jpeg: "jpeg"
        case .png: "png"
        case .gif: "gif"
        case .heic: "heic"
        case .webp: "webp"
        case .avif: "avif"
        case .bmp: "bmp"
        case .tiff: "tiff"
        case .ico: "ico"
        case .jpeg2000: "jpeg2000"
        case .jxl: "jxl"
        case .mp4: "mp4"
        case .m4v: "m4v"
        case .mov: "mov"
        default: rawValue
        }
    }
}

/// The name of the type of the value without its module, such as
/// `"ImageDecoders.Default"`.
func diagnosticsTypeName(of value: Any) -> String {
    let name = String(reflecting: type(of: value))
    guard let dot = name.firstIndex(of: "."), !name.hasPrefix("(") else {
        return name
    }
    return String(name[name.index(after: dot)...])
}

// MARK: - Conversions

extension PlatformImage {
    /// The size of the bitmap, measured the way ``ImageCache`` measures its cost.
    var diagnosticsPixelSize: ImagePipeline.Diagnostics.PixelSize? {
        guard let cgImage else { return nil }
        return .init(width: cgImage.width, height: cgImage.height)
    }
}

extension TaskPriority {
    var requestPriority: ImageRequest.Priority {
        switch self {
        case .veryLow: .veryLow
        case .low: .low
        case .normal: .normal
        case .high: .high
        case .veryHigh: .veryHigh
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
