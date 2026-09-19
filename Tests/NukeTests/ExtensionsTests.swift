// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
import os
@testable import Nuke

@Suite(.timeLimit(.minutes(5)))
struct ExtensionsTests {

    // MARK: - URL.isLocalResource

    @Test(arguments: [
        "file:///var/tmp/image.jpeg",
        "FILE:///var/tmp/image.jpeg",
        "File:///var/tmp/image.jpeg"
    ])
    func fileURLIsLocalResourceRegardlessOfSchemeCase(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(url.isLocalResource)
    }

    @Test(arguments: [
        "data:image/jpeg;base64,AAAA",
        "Data:image/jpeg;base64,AAAA",
        "DATA:image/jpeg;base64,AAAA"
    ])
    func dataURLIsLocalResourceRegardlessOfSchemeCase(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(url.isLocalResource)
    }

    @Test(arguments: [
        "http://example.com/image.jpeg",
        "https://example.com/image.jpeg",
        "HTTP://example.com/image.jpeg",
        "ftp://example.com/image.jpeg",
        "filesystem://example.com/image.jpeg",
        "database:image.jpeg"
    ])
    func remoteURLIsNotLocalResource(string: String) throws {
        let url = try #require(URL(string: string))
        #expect(!url.isLocalResource)
    }

    @Test func urlWithoutSchemeIsNotLocalResource() throws {
        let url = try #require(URL(string: "images/image.jpeg"))
        #expect(url.scheme == nil)
        #expect(!url.isLocalResource)
    }

    // MARK: - String.sha1

    /// `DataCache` names its files with the digest, so it must stay the
    /// standard SHA-1 of the UTF-8 bytes in lowercase hex.
    @Test(arguments: [
        ("", "da39a3ee5e6b4b0d3255bfef95601890afd80709"),
        ("abc", "a9993e364706816aba3e25717850c26c9cd0d89d"),
        ("The quick brown fox jumps over the lazy dog", "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12"),
        ("日本語", "c12140a0ffb4e56481b4fe0a7a25040c2eafa9ca"),
        ("https://example.com/image.jpeg?w=100&h=100", "b0bff4cbaa3458057ed550dd795cb0285219a077")
    ])
    func sha1MatchesReferenceDigest(input: String, digest: String) {
        #expect(input.sha1 == digest)
    }

    // MARK: - ImageRequest.Priority

    @Test func requestPriorityMapsToTheSameTaskPriority() {
        #expect(ImageRequest.Priority.veryLow.taskPriority == .veryLow)
        #expect(ImageRequest.Priority.low.taskPriority == .low)
        #expect(ImageRequest.Priority.normal.taskPriority == .normal)
        #expect(ImageRequest.Priority.high.taskPriority == .high)
        #expect(ImageRequest.Priority.veryHigh.taskPriority == .veryHigh)
    }

    // MARK: - AnonymousCancellable

    @Test func anonymousCancellableCallsTheClosureOnCancel() {
        // Given
        let count = OSAllocatedUnfairLock(initialState: 0)
        let cancellable = AnonymousCancellable { count.withLock { $0 += 1 } }
        #expect(count.withLock { $0 } == 0)

        // When
        cancellable.cancel()

        // Then
        #expect(count.withLock { $0 } == 1)
    }

    // MARK: - performInBackground

    /// The pipeline decodes and processes images with it, so it must never
    /// run the work on the main thread.
    @MainActor
    @Test func performInBackgroundLeavesTheMainThread() async {
        let isMainThread = await performInBackground { Thread.isMainThread }
        #expect(!isMainThread)
    }
}
