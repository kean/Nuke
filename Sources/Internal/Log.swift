// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation
import os

final class Log {
    private let log: OSLog
    private let name: StaticString
    private let signpostsEnabled: Bool

    init(_ log: OSLog, _ name: StaticString, _ signpostsEnabled: Bool = ImagePipeline.Configuration.isSignpostLoggingEnabled) {
        self.log = log
        self.name = name
        self.signpostsEnabled = signpostsEnabled
    }

    // MARK: Signposts

    func signpost(_ type: SignpostType, _ message: @autoclosure () -> String) {
        guard signpostsEnabled else { return }
        signpost(type, "%{public}s", message())
    }

    func signpost(_ type: SignpostType) {
        guard signpostsEnabled else { return }
        if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
            os_signpost(type.os, log: log, name: name, signpostID: signpostID)
        }
    }

    func signpost<T>(_ message: @autoclosure () -> String? = nil, _ work: () -> T) -> T {
        signpost(.begin)
        let result = work()
        signpost(.end)
        return result
    }

    // Unfortunately, there is no way to wrap os_signpost which takes variadic
    // arguments, because Swift implicitly wraps `arguments CVarArg...` from `log`
    // into an array and passes the array to `os_signpost` which is not what
    // we expect. So in this scenario we have to limit the number of arguments
    // to one, there is no way to pass more. For more info see https://stackoverflow.com/questions/50937765/why-does-wrapping-os-log-cause-doubles-to-not-be-logged-correctly
    func signpost(_ type: SignpostType, _ format: StaticString, _ argument: CVarArg) {
        guard signpostsEnabled else { return }
        if #available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *) {
            os_signpost(type.os, log: log, name: name, signpostID: signpostID, format, argument)
        }
    }

    @available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
    var signpostID: OSSignpostID {
        OSSignpostID(log: log, object: self)
    }
}

private let byteFormatter = ByteCountFormatter()

extension Log {
    static func bytes(_ count: Int) -> String {
        bytes(Int64(count))
    }

    static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: count)
    }
}

enum SignpostType {
    case begin, event, end

    @available(OSX 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
    var os: OSSignpostType {
        switch self {
        case .begin: return .begin
        case .event: return .event
        case .end: return .end
        }
    }
}
