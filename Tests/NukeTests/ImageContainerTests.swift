// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ImageContainerTests {

    // MARK: - Copy-on-Write

    /// A mutable property of a container, rendered as a string so that two
    /// containers can be compared field by field. The image and the animation
    /// are compared by identity.
    enum Field: String, CaseIterable, Sendable {
        case image, type, isPreview, data, animation, userInfo

        func value(in container: ImageContainer) -> String {
            switch self {
            case .image: "\(ObjectIdentifier(container.image))"
            case .type: container.type?.rawValue ?? "nil"
            case .isPreview: "\(container.isPreview)"
            case .data: container.data.map { "\(Array($0))" } ?? "nil"
            case .animation: container.animation.map { "\(ObjectIdentifier($0))" } ?? "nil"
            case .userInfo: container.userInfo.map { "\($0.key.rawValue)=\($0.value)" }.sorted().joined(separator: ",")
            }
        }

        /// Changes the field to a value different from the one in
        /// ``ImageContainerTests/makeConfiguredContainer()`` and returns the
        /// new value, as ``value(in:)`` renders it.
        func mutate(_ container: inout ImageContainer) -> String {
            switch self {
            case .image:
                let image = Test.rgbImage(width: 2, height: 2)
                container.image = image
                return "\(ObjectIdentifier(image))"
            case .type:
                container.type = .png
                return AssetType.png.rawValue
            case .isPreview:
                container.isPreview = false
                return "false"
            case .data:
                container.data = Data([0xFF])
                return "[255]"
            case .animation:
                container.animation = nil
                return "nil"
            case .userInfo:
                container.userInfo["key"] = "other"
                return "key=other"
            }
        }
    }

    /// A container with every mutable property moved away from its default.
    static func makeConfiguredContainer() -> ImageContainer {
        ImageContainer(
            image: Test.image,
            type: .jpeg,
            isPreview: true,
            data: Data([0x01, 0x02]),
            animation: Test.animatedGIFSource(frameCount: 4),
            userInfo: ["key": "value"]
        )
    }

    static func snapshot(of container: ImageContainer) -> [Field: String] {
        Dictionary(uniqueKeysWithValues: Field.allCases.map { ($0, $0.value(in: container)) })
    }

    static func changedFields(from lhs: [Field: String], to rhs: [Field: String]) -> [Field] {
        Field.allCases.filter { lhs[$0] != rhs[$0] }
    }

    /// Every setter goes through the one copy-on-write `mutate`: a write to a
    /// copy that shares the storage with the original must leave the original
    /// as it was.
    @Test(arguments: Field.allCases)
    func mutatingCopyLeavesOriginalIntact(_ field: Field) {
        // GIVEN
        let original = Self.makeConfiguredContainer()
        let before = Self.snapshot(of: original)

        // WHEN
        var copy = original
        let value = field.mutate(&copy)

        // THEN
        #expect(Self.snapshot(of: original) == before)
        #expect(field.value(in: copy) == value)
        #expect(Self.changedFields(from: before, to: Self.snapshot(of: copy)) == [field])
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
