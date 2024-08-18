// The MIT License (MIT)
//
// Copyright (c) 2015-2024 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Fetches data using the publisher provided with the request.
/// Unlike `TaskFetchOriginalImageData`, there is no resumable data involved.
final class TaskFetchWithClosure: AsyncPipelineTask<(Data, URLResponse?)> {
    private lazy var data = Data()

    override func start() {
        if request.options.contains(.skipDataLoadingQueue) {
            loadData(finish: { /* do nothing */ })
        } else {
            // Wrap data request in an operation to limit the maximum number of
            // concurrent data tasks.
            operation = pipeline.configuration.dataLoadingQueue.add { [weak self] finish in
                guard let self else {
                    return finish()
                }
                Task { @ImagePipelineActor in
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

        guard let closure = request.closure else {
            send(error: .dataLoadingFailed(error: URLError(.unknown))) // This is just a placeholder error, never thrown
            return assertionFailure("This should never happen")
        }

        let task = Task { @ImagePipelineActor in
            do {
                let data = try await closure()
                guard !data.isEmpty else {
                    throw ImagePipeline.Error.dataIsEmpty
                }
                storeDataInCacheIfNeeded(data)
                send(value: (data, nil), isCompleted: true)
            } catch {
                send(error: .dataLoadingFailed(error: error))
            }
            finish() // Finish the operation!
        }
        onCancelled = {
            finish()
            task.cancel()
        }
    }
}
