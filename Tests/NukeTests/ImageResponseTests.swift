// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImageResponseTests {

    @Test func imageForwardsFromContainer() {
        let container = ImageContainer(image: Test.image)
        let response = ImageResponse(container: container, request: Test.request)
        #expect(response.image === container.image)
    }

    @Test func isPreviewForwardsFromContainer() {
        let container = ImageContainer(image: Test.image, isPreview: true)
        let response = ImageResponse(container: container, request: Test.request)
        #expect(response.isPreview == true)
    }

    @Test func defaultsForOptionalProperties() {
        let response = ImageResponse(container: ImageContainer(image: Test.image), request: Test.request)
        #expect(response.urlResponse == nil)
        #expect(response.cacheType == nil)
    }

    @Test func cacheTypeValuesAreDistinct() {
        #expect(ImageResponse.CacheType.memory != .disk)
    }

    @Test func initializerStoresEveryArgument() {
        // Given
        let container = ImageContainer(image: Test.image, type: .png, isPreview: true)
        let request = ImageRequest(url: Test.url).with { $0.imageID = "response-id" }
        let urlResponse = URLResponse(url: Test.url, mimeType: "image/jpeg", expectedContentLength: 10, textEncodingName: nil)

        // When
        let response = ImageResponse(container: container, request: request, urlResponse: urlResponse, cacheType: .disk)

        // Then
        #expect(response.container.image === container.image)
        #expect(response.container.type == .png)
        #expect(response.isPreview == true)
        #expect(response.request.imageID == "response-id")
        #expect(response.urlResponse === urlResponse)
        #expect(response.cacheType == .disk)
    }

    /// `image` and `isPreview` are views of the container, not copies taken
    /// at initialization.
    @Test func imageAndIsPreviewFollowContainer() {
        // Given
        var response = ImageResponse(container: ImageContainer(image: Test.image), request: Test.request)
        let replacement = Test.rgbImage(width: 2, height: 2)

        // When
        response.container.image = replacement
        response.container.isPreview = true

        // Then
        #expect(response.image === replacement)
        #expect(response.isPreview == true)
    }

    @Test func mutatingCopyLeavesOriginalIntact() {
        // Given
        let original = ImageResponse(container: ImageContainer(image: Test.image), request: Test.request, cacheType: .memory)
        let originalImage = original.image

        // When
        var copy = original
        copy.container.image = Test.rgbImage(width: 2, height: 2)
        copy.container.isPreview = true
        copy.cacheType = nil
        copy.request.priority = .veryHigh

        // Then
        #expect(original.image === originalImage)
        #expect(original.isPreview == false)
        #expect(original.cacheType == .memory)
        #expect(original.request.priority == .normal)
    }
}
