// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import DFCache
import Nuke

public struct DFCacheCacheLookupFailed: Error {}

extension DFCache: Nuke.DataCaching {
    public func setResponse(_ response: CachedURLResponse, for request: URLRequest) {
        guard let key = makeKey(for: request) else { return }
        store(response, forKey: key)
    }
    
    public func response(for request: URLRequest, token: CancellationToken?) -> Promise<CachedURLResponse> {
        return Promise() { fulfill, reject in
            if let key = makeKey(for: request) {
                cachedObject(forKey: key, completion: {
                    if let object = $0 as? CachedURLResponse {
                        fulfill(object)
                    } else {
                        reject(DFCacheCacheLookupFailed())
                    }
                })
            } else {
                reject(DFCacheCacheLookupFailed())
            }
        }
    }
    
    private func makeKey(for request: URLRequest) -> String? {
        return request.url?.absoluteString
    }
}
