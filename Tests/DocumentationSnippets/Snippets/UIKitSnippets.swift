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
        ImageLoader.load(url, into: imageView)
    }

    // MARK: - Cell Reuse

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Cell", for: indexPath) as! ImageCell
        // Any previous load into this cell's imageView is cancelled automatically.
        ImageLoader.load(items[indexPath.item].imageURL, into: cell.imageView)
        return cell
    }

    // MARK: - Placeholder and Failure Images

    func placeholderAndFailureImage() {
        ImageLoader.load(url, into: imageView, presentation: .init(
            placeholder: UIImage(named: "placeholder"),
            failureImage: UIImage(named: "error")
        ))
    }

    // MARK: - Transitions

    func transitions() {
        ImageLoader.load(url, into: imageView, presentation: .init(
            transition: .fadeIn(duration: 0.3)
        ))
    }

    func namedPresentation() {
        ImageLoader.load(url, into: imageView, presentation: .thumbnail)
    }

    // MARK: - Processors and Request Options

    func processors() {
        let request = ImageRequest(
            url: url,
            processors: [.resize(width: 320)]
        )
        ImageLoader.load(request, into: imageView)
    }

    func attachedLoader() {
        let loader = ImageLoader.loader(for: imageView)
        loader.keepsPreviousImage = true
        loader.priority = .high
    }

    // MARK: - Awaiting the Outcome

    func awaitingTheOutcome() {
        let handle = ImageLoader.load(url, into: imageView)
        Task {
            do {
                let response = try await handle.response
                print("Loaded image from: \(response.urlResponse?.url?.absoluteString ?? "cache")")
            } catch {
                print("Failed to load image: \(error)")
            }
        }
    }

    // MARK: - Drawing the State Yourself

    func render(into cell: CaptionedCell) {
        ImageLoader.load(url, into: cell) { cell, state in
            cell.posterView.image = state.image
            cell.spinner.isHidden = !state.isLoading
        }
    }
}

extension ImageLoader.Presentation {
    static let thumbnail = ImageLoader.Presentation(
        placeholder: UIImage(named: "placeholder"),
        transition: .fadeIn(duration: 0.25)
    )
}

private final class CaptionedCell: UICollectionViewCell {
    let posterView = UIImageView()
    let spinner = UIActivityIndicatorView()
}

private final class PosterCell: UICollectionViewCell, ImageLoader.Delegate {
    private let loader = ImageLoader()
    private let posterView = UIImageView()
    private let progressView = UIProgressView()

    func configure(with url: URL) {
        loader.delegate = self
        loader.load(url)
    }

    func imageLoader(_ loader: ImageLoader, didUpdate state: ImageLoader.State) {
        posterView.image = state.image
        progressView.progress = state.progress.fraction
        progressView.isHidden = !state.isLoading
    }
}

#endif
