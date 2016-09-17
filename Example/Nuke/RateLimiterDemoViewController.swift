// The MIT License (MIT)
//
// Copyright (c) 2016 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

class RateLimiterDemoViewController: BasicDemoViewController {
    
    override func loadView() {
        super.loadView()
        
        // We don't want default Deduplicator to affect the results
        // We don't want a memory cache either (but we take care of it
        // using memoryCacheOptions anyway).
        let loader = Loader(loader: DataLoader(), decoder: DataDecoder(), cache: nil)
        manager = Manager(loader: loader, cache: nil)
        
        itemsPerRow = 6
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    
        for _ in 0..<10 {
            self.photos.append(contentsOf: self.photos)
        }
    }
    
    override func makeRequest(with url: URL) -> Request {
        let urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        var request = Request(urlRequest: urlRequest)
        request.memoryCacheOptions.readAllowed = false
        request.memoryCacheOptions.writeAllowed = false
        return request
    }
}
