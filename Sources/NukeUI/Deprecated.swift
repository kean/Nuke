// The MIT License (MIT)
//
// Copyright (c) 2015-2023 Alexander Grebenyuk (github.com/kean).

import Foundation
import Nuke

@available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 10.16, *)
extension LazyImage {
    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onStart(_ closure: @escaping (ImageTask) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onPreview(_ closure: @escaping (ImageResponse) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onProgress(_ closure: @escaping (ImageTask.Progress) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onSuccess(_ closure: @escaping (ImageResponse) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onFailure(_ closure: @escaping (Error) -> Void) -> Self { self }

    @available(*, deprecated, message: "This callback no longer gets called. Please create a custom view and use ``FetchImage`` directly to set these callbacks")
    public func onCompletion(_ closure: @escaping (Result<ImageResponse, Error>) -> Void) -> Self { self }

#if !os(watchOS)
    @available(*, deprecated, message: "ImageView is deprecated starting with version 12.0")
    public func onCreated(_ configure: ((ImageView) -> Void)?) -> Self { self }
#endif
}
