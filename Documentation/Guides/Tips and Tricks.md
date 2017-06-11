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


## Using RxNuke

[RxNuke](https://github.com/kean/RxNuke) adds [RxSwift](https://github.com/ReactiveX/RxSwift) extensions for Nuke and enables many common use cases:

- Going From Low to High Resolution
- Loading the First Available Image
- Showing Stale Image While Validating It
- Load Multiple Images, Display All at Once
- Auto Retry
- Tracking Activities

And [many more...](https://github.com/kean/RxNuke#use-cases)
