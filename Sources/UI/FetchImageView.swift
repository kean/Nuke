// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import SwiftUI
import Combine

/// Loads an image with the given request and displays it.
@available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, *)
public struct FetchImageView: View {
    private let request: ImageRequest?
    private let imageId: String
    @StateObject private var image = FetchImage()

    init(_ request: ImageRequestConvertible?) {
        self.request = request?.asImageRequest()
        self.imageId = self.request?.preferredImageId ?? ""
    }

    public var body: some View {
        ZStack {
            image.view?
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        }
        .onAppear(perform: load)
        .onChange(of: imageId) { _ in load() }
        .onDisappear(perform: image.reset)
    }

    func load() {
        if let request = self.request {
            image.load(request)
        }
    }
}
