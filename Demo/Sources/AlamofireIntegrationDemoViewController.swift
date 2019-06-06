// The MIT License (MIT)
//
// Copyright (c) 2015-2019 Alexander Grebenyuk (github.com/kean).

import UIKit
import Nuke
import Alamofire

final class AlamofireIntegrationDemoViewController: BasicDemoViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        pipeline = ImagePipeline {
            $0.dataLoader = AlamofireDataLoader()

            $0.imageCache = ImageCache()
        }
    }
}

/// Implements data loading using Alamofire framework.
final class AlamofireDataLoader: Nuke.DataLoading {
    let manager: Alamofire.SessionManager

    /// Initializes the receiver with a given Alamofire.SessionManager.
    /// - parameter manager: Alamofire.SessionManager.default by default.
    init(manager: Alamofire.SessionManager = Alamofire.SessionManager.default) {
        self.manager = manager
    }

    // MARK: DataLoading

    /// Loads data using Alamofire.SessionManager.
    func loadData(with request: URLRequest, didReceiveData: @escaping (Data, URLResponse) -> Void, completion: @escaping (Error?) -> Void) -> Cancellable {
        // Alamofire.SessionManager automatically starts requests as soon as they are created (see `startRequestsImmediately`)
        let task = self.manager.request(request)
        task.stream { [weak task] data in
            guard let response = task?.response else { return } // Never nil
            didReceiveData(data, response)
        }
        task.response { response in
            completion(response.error)
        }
        return task
    }
}

extension Alamofire.DataRequest: Nuke.Cancellable {}
