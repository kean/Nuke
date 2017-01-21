// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import DFCache
import Nuke

extension DFCache: Nuke.DataCaching {
    public func setResponse(_ response: CachedURLResponse, for request: URLRequest) {
        guard let key = makeKey(for: request) else { return }
        store(response, forKey: key)
    }
    
    public func response(for request: URLRequest, token: CancellationToken?, completion: @escaping (CachedURLResponse?) -> Void) {
            if let key = makeKey(for: request) {
                cachedObject(forKey: key, completion: {
                    completion(($0 as? CachedURLResponse))
                })
            } else {
                completion(nil)
            }

    }
    
    private func makeKey(for request: URLRequest) -> String? {
        return request.url?.absoluteString
    }
}
