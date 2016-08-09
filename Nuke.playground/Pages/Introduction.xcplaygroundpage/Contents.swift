import Nuke
import UIKit
import XCPlayground

/*:
## Why use Nuke?

Nuke is a pure Swift framework for loading, caching, processing, displaying and preheating images. It takes care of all those things so you don't have to.

Nuke's goal is to solve those complex tasks in a most efficient and user-friendly manner. Without compromising on extensibility.
*/

/*:
### Zero Config
*/
Nuke.Loader.shared.loadImage(with: URL(string: "https://farm8.staticflickr.com/7315/16455839655_7d6deb1ebf_z_d.jpg")!).then {
    let image = $0
}

/*:
### Adding Request Options
*/
let urlRequest = URLRequest(url: URL(string: "https://farm4.staticflickr.com/3892/14940786229_5b2b48e96c_z_d.jpg")!, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 60)
let request = Request(urlRequest: urlRequest).process(with: Decompressor(targetSize: CGSize(width: 200.0, height: 200.0), contentMode: .aspectFill))

Nuke.Loader.shared.loadImage(with: request, token: nil).then {
    let image = $0
}

XCPlaygroundPage.currentPage.needsIndefiniteExecution = true

//: [Next](@
