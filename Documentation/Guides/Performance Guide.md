### Create `URL`s in a Background

`URL` initializer is expensive because it parses the input string. It might take more time than the call to `Nuke.loadImage(with:into:)` itself. Make sure to create the `URL` objects in a background. For example, it might be a good idea to create `URL` when parsing JSON to create your model objects.


### Avoiding Decompression on the Main Thread

When you create `UIImage` object form data, the data doesn't get decoded immediately. It is decoded the first time it is used - for example, when you display the image in an image view. Decoding is a resource-intensive operation, if you do it on the main thread you might see dropped frames, especially for image formats like JPEG.

To prevent decoding happening on the main thread, Nuke perform it in a background for you. But for even better performance it is recommended to downsample the images. To do so create a request with a target view size:

```swift
ImageRequest(url: url, targetSize: CGSize(width: 640, height: 320), contentMode: .aspectFill)
```

> **Warning:** target size is in pixels!

> See [Image and Graphics Best Practices](https://developer.apple.com/videos/play/wwdc2018/219) to learn more about image decoding and downsampling.


### Request Priorities

Nuke allows you to set request priorities and update them dynamically after the task has already started.

Request priorities are especially important for prefetching. You don't want prefetching tasks to interfere with the normal requests thus it is important to reduce their priority.

You might also want to dynamically change the priority of the tasks while leaving the screen. For example, if you have a screen with a collection view full of images and when the user taps of the images to open it fullscreen, you might reduce the priority of the tasks initiated by the first, now disappearing from the view screens. One way to do that is to override `willMove(toWindow:)` method of the `UIView`:

```swift
class ImageView: UIView {
    let task: ImageTask?

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)

        task?.priority = newWindow == nil ? .low : .high
    }
}
```


### Avoiding Excessive Cancellations

Don't cancel outstanding requests when it is not necessary. For instance, when reloading `UITableView` you might want to check if the cell that you are updating is already loading the same image and keep the pending request running.
