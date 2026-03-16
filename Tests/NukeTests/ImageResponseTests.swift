// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
@testable import Nuke

@Suite(.timeLimit(.minutes(2)))
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
}
