// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

import Testing
import Foundation
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
}
