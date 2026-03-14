// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite struct ImageDecodersEmptyTests {
    @Test func isAsynchronousReturnsFalse() {
        let decoder = ImageDecoders.Empty()
        #expect(decoder.isAsynchronous == false)
    }

    @Test func isProgressiveDefaultIsFalse() {
        let decoder = ImageDecoders.Empty()
        #expect(decoder.isProgressive == false)
    }

    @Test func isProgressiveWhenEnabled() {
        let decoder = ImageDecoders.Empty(isProgressive: true)
        #expect(decoder.isProgressive == true)
    }

    @Test func decodeReturnsContainerWithData() throws {
        let decoder = ImageDecoders.Empty()
        let data = Data("test-data".utf8)

        let container = try decoder.decode(data)

        #expect(container.data == data)
        #expect(container.type == nil)
        #expect(container.userInfo.isEmpty)
    }

    @Test func decodeWithAssetType() throws {
        let decoder = ImageDecoders.Empty(assetType: .png)
        let data = Data("test".utf8)

        let container = try decoder.decode(data)

        #expect(container.type == .png)
        #expect(container.data == data)
    }

    @Test func decodePartiallyDownloadedDataReturnsNilWhenNotProgressive() {
        let decoder = ImageDecoders.Empty(isProgressive: false)
        let data = Data("partial".utf8)

        let result = decoder.decodePartiallyDownloadedData(data)

        #expect(result == nil)
    }

    @Test func decodePartiallyDownloadedDataReturnsContainerWhenProgressive() {
        let decoder = ImageDecoders.Empty(assetType: .jpeg, isProgressive: true)
        let data = Data("partial".utf8)

        let result = decoder.decodePartiallyDownloadedData(data)

        #expect(result != nil)
        #expect(result?.data == data)
        #expect(result?.type == .jpeg)
    }
}
