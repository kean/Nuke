// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

/// Takes what a pipeline reports to a model: the handlers that receive the
/// reports are made before the model exists. `@MainActor`, which makes it
/// `Sendable`.
@MainActor
final class DemoRelay<Model: AnyObject> {
    weak var model: Model?
}
