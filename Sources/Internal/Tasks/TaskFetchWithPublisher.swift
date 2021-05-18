// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches data using the publisher provided with the request.
/// Unlike `TaskFetchOriginalImageData`, there is no resumable data involved.
final class TaskFetchWithPublisher: ImagePipelineTask<(Data, URLResponse?)> {
    private lazy var data = Data()

    override func start() {
        // Wrap data request in an operation to limit the maximum number of
        // concurrent data tasks.
        operation = pipeline.configuration.dataLoadingQueue.add { [weak self] finish in
            guard let self = self else {
                return finish()
            }
            self.async {
                self.loadData(finish: finish)
            }
        }
    }

    // This methods gets called inside data loading operation (Operation).
    private func loadData(finish: @escaping () -> Void) {
        guard !isDisposed else {
            return finish()
        }

        guard let publisher = request.publisher else {
            self.send(error: .dataLoadingFailed(URLError(.unknown, userInfo: [:])))
            return assertionFailure("This should never happen")
        }

        let cancellable = publisher.sink(receiveCompletion: { [weak self] result in
            finish() // Finish the operation!
            guard let self = self else { return }
            self.async {
                switch result {
                case .finished:
                    #warning("make sure we are never sending an empty value")
                    self.send(value: (self.data, nil), isCompleted: true)
                case .failure(let error):
                    self.send(error: .dataLoadingFailed(error))
                }
            }
        }, receiveValue: { [weak self] data in
            guard let self = self else { return }
            self.async {
                #warning("add progressive decoding support")
                self.data.append(data)
            }
        })

        onCancelled = {
            cancellable.cancel()
        }
    }
}
