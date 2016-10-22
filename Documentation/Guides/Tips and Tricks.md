## Display a placeholder

```swift
imageView.image = UIImage(named: "placeHolder")
Nuke.loadImage(with: url, into: imageView)
```

If you worry about performance:
```swift
Nuke.loadImage(with: url, into: imageView)
if imageView.image == nil {
    imageView.image = UIImage(named: "placeHolder")
}
```

You can also add your own extension method to `Nuke.Manager` that has a placeholder parameter.

## Show a low-res image first and swap to a higher-res one when it arrives

The idea is two have two separate image views: one for a low-res image, one for the high-res one. Here's a fully functional example in a collection view:

```swift
override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseID, for: indexPath) as! CellWithPlaceholder

    cell.imageView.image = nil
    cell.placeholderView.image = nil
    cell.placeholderView.alpha = 1

    let placeholder = URL(string: "https://cloud.githubusercontent.com/assets/1567433/18921748/a45de236-85ae-11e6-8c11-f26453e384b6.png")!
    manager.loadImage(with: placeholder, into: cell.placeholderView)

    manager.loadImage(with: Request(url: photos[indexPath.row]), into: cell.imageView) { [weak cell] response, _ in
        if case let .fulfilled(image) = response {
            cell?.placeholderView.alpha = 0
            cell?.imageView.image = image
        }
}

//    In case you want some nice cross-dissolve animation between placeholder and the actual image
//    manager.loadImage(with: Request(url: photos[indexPath.row]), into: cell.imageView) { [weak cell] response, isFromMemCache in
//        if case let .fulfilled(image) = response {
//            cell?.imageView.image = image
//            cell?.imageView.alpha = 0
//            UIView.animate(withDuration: isFromMemCache ? 0.0 : 0.33) {
//                cell?.placeholderView.alpha = 0
//                cell?.imageView.alpha = 1
//            }
//        }
//    }

return cell
}
```

Here's a `CellWithPlaceholder`:

```swift
class CellWithPlaceholder: UICollectionViewCell {
    let placeholderView: UIImageView
    let imageView: UIImageView

    override init(frame: CGRect) {
        placeholderView = UIImageView()
        imageView = UIImageView()

        super.init(frame: frame)

        contentView.backgroundColor = UIColor(white: 235.0 / 255.0, alpha: 1.0)

        for view in [placeholderView, imageView] {
            contentView.addSubview(view)
            view.contentMode = .scaleAspectFill
            view.clipsToBounds = true
            view.translatesAutoresizingMaskIntoConstraints = false
            for attr in [.top, .leading, .bottom, .trailing] as [NSLayoutAttribute] {
                addConstraint(NSLayoutConstraint(item: view, attribute: attr, relatedBy: .equal, toItem: self, attribute: attr, multiplier: 1, constant: 0))
            }
        }
    }
}
```
