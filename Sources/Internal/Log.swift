// The MIT License (MIT)
//
// Copyright (c) 2015-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

func signpost(_ log: OSLog, _ object: AnyObject, _ name: StaticString, _ type: OSSignpostType) {
    guard ImagePipeline.Configuration.isSignpostLoggingEnabled else { return }

    let signpostId = OSSignpostID(log: log, object: object)
    os_signpost(type, log: log, name: name, signpostID: signpostId)
}

func signpost(_ log: OSLog, _ object: AnyObject, _ name: StaticString, _ type: OSSignpostType, _ message: @autoclosure () -> String) {
    guard ImagePipeline.Configuration.isSignpostLoggingEnabled else { return }

    let signpostId = OSSignpostID(log: log, object: object)
    os_signpost(type, log: log, name: name, signpostID: signpostId, "%{public}s", message())
}

func signpost<T>(_ log: OSLog, _ name: StaticString, _ message: @autoclosure () -> String? = nil, _ work: () throws -> T) rethrows -> T {
    guard ImagePipeline.Configuration.isSignpostLoggingEnabled else { return try work() }

    let signpostId = OSSignpostID(log: log)
    if let message = message() {
        os_signpost(.begin, log: log, name: name, signpostID: signpostId, "%{public}s", message)
    } else {
        os_signpost(.begin, log: log, name: name, signpostID: signpostId)
    }
    let result = try work()
    os_signpost(.end, log: log, name: name, signpostID: signpostId)
    return result
}

var log: OSLog = .disabled

private let byteFormatter = ByteCountFormatter()

enum Formatter {
    static func bytes(_ count: Int) -> String {
        bytes(Int64(count))
    }

    static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: count)
    }
}
