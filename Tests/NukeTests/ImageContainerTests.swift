// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(1)))
struct ImageContainerTests {

    // MARK: - Copy-on-Write

    @Test func copyOnWriteIsPreview() {
        // GIVEN
        let a = ImageContainer(image: Test.image, isPreview: false)

        // WHEN - copy and mutate
        var b = a
        b.isPreview = true

        // THEN - original is unchanged
        #expect(a.isPreview == false)
        #expect(b.isPreview == true)
    }

    @Test func copyOnWriteType() {
        // GIVEN
        let a = ImageContainer(image: Test.image, type: .jpeg)

        // WHEN
        var b = a
        b.type = .png

        // THEN
        #expect(a.type == .jpeg)
        #expect(b.type == .png)
    }

    @Test func copyOnWriteUserInfo() {
        // GIVEN
        let a = ImageContainer(image: Test.image)

        // WHEN
        var b = a
        b.userInfo["key"] = "value"

        // THEN original is unaffected
        #expect(a.userInfo.isEmpty)
        #expect(b.userInfo["key"] as? String == "value")
    }

    @Test func copyOnWriteData() {
        // GIVEN
        let originalData = Data([0x01, 0x02])
        let a = ImageContainer(image: Test.image, data: originalData)

        // WHEN
        var b = a
        b.data = Data([0xFF])

        // THEN
        #expect(a.data == originalData)
        #expect(b.data == Data([0xFF]))
    }

    // MARK: - UserInfoKey

    @Test func userInfoKeyEquality() {
        let k1 = ImageContainer.UserInfoKey("test-key")
        let k2 = ImageContainer.UserInfoKey("test-key")
        let k3 = ImageContainer.UserInfoKey("other-key")
        #expect(k1 == k2)
        #expect(k1 != k3)
        #expect(k1.hashValue == k2.hashValue)
    }

    @Test func userInfoKeyExpressibleByStringLiteral() {
        let key: ImageContainer.UserInfoKey = "my-key"
        #expect(key.rawValue == "my-key")
    }

    // MARK: - Default Values

    @Test func defaultValuesAreCorrect() {
        let container = ImageContainer(image: Test.image)
        #expect(container.isPreview == false)
        #expect(container.data == nil)
        #expect(container.type == nil)
        #expect(container.userInfo.isEmpty)
    }
}
