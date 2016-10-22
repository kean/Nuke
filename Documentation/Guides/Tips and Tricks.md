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

```swift
override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseID, for: indexPath)
    
    cell.imageView.image = nil

    let placeholder = URL(string: "https://cloud.githubusercontent.com/assets/1567433/18921748/a45de236-85ae-11e6-8c11-f26453e384b6.png")!
    manager.loadImage(with: placeholder, into: cell) { [weak cell] response, _ in
        guard let cell = cell else { return }
        if cell.imageView.image == nil, case let .fulfilled(image) = response {
            cell.imageView.image = image
        }
    }
    
    manager.loadImage(with: Request(url: photos[indexPath.row]), into: cell.imageView)

//  In case you want to customize default animation:
//
//  manager.loadImage(with: Request(url: photos[indexPath.row]), into: cell.imageView) { [weak cell] response, isFromCache in
//      guard let cell = cell else { return }
//      guard case let .fulfilled(image) = response else { return }
//
//      cell.imageView.image = image
//
//      if !isFromCache { // Run cross-fade animations
//          let animation = CATransition()
//          animation.duration = 0.33
//          animation.type = kCATransitionFade
//          cell.imageView.layer.add(animation, forKey: "imageTransition")
//      }
//   }

    return cell
}
```
