// The MIT License (MIT)
//
// Copyright (c) 2015-2018 Alexander Grebenyuk (github.com/kean).

import Nuke
import XCTest

private final class BundleToken {}

let defaultURL = URL(string: "http://test.com")!

let defaultImage: Image = {
    let bundle = Bundle(for: BundleToken.self)
    let URL = bundle.url(forResource: "fixture", withExtension: "jpeg")
    let data = try! Data(contentsOf: URL!)
    return Nuke.ImageDecoder().decode(data: data, isFinal: true)!
}()

enum Test {
    static func data(name: String, extension ext: String) -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let URL = bundle.url(forResource: name, withExtension: ext)
        return try! Data(contentsOf: URL!)
    }
}

extension String: Error {}
