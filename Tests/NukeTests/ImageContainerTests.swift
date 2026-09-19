// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
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

    @Test func copyOnWriteAnimation() throws {
        // GIVEN
        let original = try #require(AnimatedImageSource(data: Test.animatedGIF(frameCount: 4)))
        let a = ImageContainer(image: Test.image, animation: original)

        // WHEN
        var b = a
        b.animation = nil

        // THEN
        #expect(a.animation === original)
        #expect(b.animation == nil)
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
        #expect(container.animation == nil)
        #expect(container.type == nil)
        #expect(container.userInfo.isEmpty)
    }

    @Test func initializerStoresEveryArgument() throws {
        // GIVEN
        let image = Test.image
        let data = Test.animatedGIF(frameCount: 2)
        let animation = try #require(AnimatedImageSource(data: data))

        // WHEN
        let container = ImageContainer(image: image, type: .gif, isPreview: true, data: data, animation: animation, userInfo: [.scanNumberKey: 3])

        // THEN
        #expect(container.image === image)
        #expect(container.type == .gif)
        #expect(container.isPreview == true)
        #expect(container.data == data)
        #expect(container.animation === animation)
        #expect(container.userInfo[.scanNumberKey] as? Int == 3)
    }

    // MARK: - Copy-on-Write (Image)

    @Test func copyOnWriteImage() {
        // GIVEN
        let original = Test.image
        let a = ImageContainer(image: original)

        // WHEN
        var b = a
        b.image = Test.rgbImage(width: 2, height: 2)

        // THEN
        #expect(a.image === original)
        #expect(b.image !== original)
    }

    /// The storage copy made on the first mutation has to carry every other
    /// field over: a field it forgets reverts to its default on the copy.
    @Test func copyKeepsEveryOtherField() throws {
        // GIVEN
        let data = Test.animatedGIF(frameCount: 2)
        let animation = try #require(AnimatedImageSource(data: data))
        let a = ImageContainer(image: Test.image, type: .gif, isPreview: true, data: data, animation: animation, userInfo: ["key": "value"])

        // WHEN
        var b = a
        b.image = Test.rgbImage(width: 2, height: 2)

        // THEN
        #expect(b.type == .gif)
        #expect(b.isPreview == true)
        #expect(b.data == data)
        #expect(b.animation === animation)
        #expect(b.userInfo["key"] as? String == "value")
    }

    // MARK: - Map

    /// Processing an image drops the data and the animation, which describe
    /// the image that went into the processor, and keeps the rest.
    @Test func mapDropsDataAndAnimation() throws {
        // GIVEN
        let data = Test.animatedGIF(frameCount: 2)
        let animation = try #require(AnimatedImageSource(data: data))
        let original = ImageContainer(image: Test.image, type: .gif, isPreview: true, data: data, animation: animation, userInfo: ["key": "value"])
        let output = Test.rgbImage(width: 2, height: 2)

        // WHEN
        let mapped = original.map { _ in output }

        // THEN
        #expect(mapped.image === output)
        #expect(mapped.data == nil)
        #expect(mapped.animation == nil)
        #expect(mapped.type == .gif)
        #expect(mapped.isPreview == true)
        #expect(mapped.userInfo["key"] as? String == "value")

        // THEN the source container is intact
        #expect(original.data == data)
        #expect(original.animation === animation)
        #expect(original.image !== output)
    }

    @Test func mapRethrowsAndLeavesContainerIntact() {
        // GIVEN
        let data = Data([0x01])
        let original = ImageContainer(image: Test.image, data: data)

        // WHEN/THEN
        #expect(throws: MockError(description: "map")) {
            _ = try original.map { _ in throw MockError(description: "map") }
        }
        #expect(original.data == data)
    }

    // MARK: - UserInfoKey

    @Test func userInfoKeyInitializersAreEquivalent() {
        // A literal argument would be coerced with `init(stringLiteral:)`
        let rawValue = "com.example/key"
        let lhs = ImageContainer.UserInfoKey(rawValue)
        let rhs: ImageContainer.UserInfoKey = "com.example/key"
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
        #expect(lhs.rawValue == rawValue)
    }
}
