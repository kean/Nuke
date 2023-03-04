// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches data using the publisher provided with the request.
/// Unlike `TaskFetchOriginalImageData`, there is no resumable data involved.
final class TaskFetchWithPublisher: ImagePipelineTask<(Data, URLResponse?)> {
    private lazy var data = Data()

    override func start() {
        if request.options.contains(.skipDataLoadingQueue) {
            loadData(finish: { /* do nothing */ })
        } else {
            // Wrap data request in an operation to limit the maximum number of
            // concurrent data tasks.
            operation = pipeline.configuration.dataLoadingQueue.add { [weak self] finish in
                guard let self = self else {
                    return finish()
                }
                self.pipeline.queue.async {
                    self.loadData { finish() }
                }
            }
        }
    }

    // This methods gets called inside data loading operation (Operation).
    private func loadData(finish: @escaping () -> Void) {
        guard !isDisposed else {
            return finish()
        }

        guard let publisher = request.publisher else {
            send(error: .dataLoadingFailed(error: URLError(.unknown))) // This is just a placeholder error, never thrown
            return assertionFailure("This should never happen")
        }

        let cancellable = publisher.sink(receiveCompletion: { [weak self] result in
            finish() // Finish the operation!
            guard let self = self else { return }
            self.pipeline.queue.async {
                self.dataTaskDidFinish(result)
            }
        }, receiveValue: { [weak self] data in
            guard let self = self else { return }
            self.pipeline.queue.async {
                self.data.append(data)
            }
        })

        onCancelled = {
            finish()
            cancellable.cancel()
        }
    }

    private func dataTaskDidFinish(_ result: PublisherCompletion) {
        switch result {
        case .finished:
            guard !data.isEmpty else {
                send(error: .dataIsEmpty)
                return
            }
            storeDataInCacheIfNeeded(data)
            send(value: (data, nil), isCompleted: true)
        case .failure(let error):
            send(error: .dataLoadingFailed(error: error))
        }
    }
}
