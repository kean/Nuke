// The MIT License (MIT)
//
// Copyright (c) 2015-2026 Alexander Grebenyuk (github.com/kean).

// Snippets from `Documentation/Nuke.docc/Essentials/uikit.md`.

#if canImport(UIKit) && !os(watchOS)

import UIKit
import NukeUI

private struct Item {
    var imageURL: URL
}

private final class ImageCell: UICollectionViewCell {
    let imageView = UIImageView()
}

@MainActor
private final class UIKitSnippets {
    let url = URL(string: "https://example.com/image")!
    let imageView = UIImageView()
    let items: [Item] = []

    // MARK: - Loading Images into UIImageView

    func loadingIntoImageView() {
        NukeUI.loadImage(with: url, into: imageView)
    }

    // MARK: - Cell Reuse

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! ImageCell
        // Any previous request on this cell's imageView is cancelled automatically.
        NukeUI.loadImage(with: items[indexPath.item].imageURL, into: cell.imageView)
        return cell
    }

    // MARK: - Placeholder and Failure Images

    func placeholderAndFailureImage() {
        var options = ImageLoadingOptions()
        options.placeholder = UIImage(named: "placeholder")
        options.failureImage = UIImage(named: "error")

        NukeUI.loadImage(with: url, options: options, into: imageView)
    }

    // MARK: - Transitions

    func transitions() {
        var options = ImageLoadingOptions()
        options.transition = .fadeIn(duration: 0.3)

        NukeUI.loadImage(with: url, options: options, into: imageView)
    }

    func sharedTransition() {
        ImageLoadingOptions.shared.transition = .fadeIn(duration: 0.25)
    }

    // MARK: - Processors and Request Options

    func processors() {
        let request = ImageRequest(
            url: url,
            processors: [.resize(width: 320)]
        )
        NukeUI.loadImage(with: request, into: imageView)
    }

    // MARK: - Tracking Progress and Completion

    func completion() {
        NukeUI.loadImage(with: url, into: imageView) { result in
            switch result {
            case .success(let response):
                print("Loaded image from: \(response.urlResponse?.url?.absoluteString ?? "cache")")
            case .failure(let error):
                print("Failed to load image: \(error)")
            }
        }
    }
}

// MARK: - Custom Views

private final class MyImageView: UIView {
    var image: UIImage?
}

extension MyImageView: ImageDisplaying {
    func nuke_display(_ container: ImageContainer?) {
        self.image = container?.image
    }
}

#endif
