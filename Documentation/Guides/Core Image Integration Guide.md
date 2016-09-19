# Overview

[Core Image](https://developer.apple.com/library/mac/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_intro/ci_intro.html) is an image processing (and more) framework from Apple. It's easy to use but it requires some boilerplate code. This guide is a starting point for using Core Image with Nuke.

There are multiple ways to use Core Image. This guide only covers a case in which you apply image filters to the `UIImage` in a background. It doesn't cover Core Image basics, but it does feature some boilerplate code.

# Core Image Usage

### Creating `CIContext`

Before we create and apply an image filter we need an instance of `CIContext` class:

```swift
let sharedCIContext = CIContext(options: [kCIContextPriorityRequestLow: true])
```

`kCIContextPriorityRequestLow` option is a new addition in iOS 8:

> If this value is true, use of the Core Image context from a background thread takes lower priority than GPU usage from the main thread, allowing your app to perform Core Image rendering without disturbing the frame rate of UI animations.

Also new in iOS 7 is support for [background renders](http://asciiwwdc.com/2014/sessions/514). All background renders automatically use the slower Core Image CPU rendering path. There is no need to manually switch between GPU and CPU rendering paths when application enters background.

### Applying Filters

And here's a `UIImage` extension that shows one way to use `CIContext` to apply an image filter and produce an  output image:

```swift
extension UIImage {
    func applyFilter(context context: CIContext = sharedCIContext, closure: CoreImage.CIImage -> CoreImage.CIImage?) -> UIImage? {
        func inputImageForImage(image: Image) -> CoreImage.CIImage? {
            if let image = image.CGImage {
                return CoreImage.CIImage(CGImage: image)
            }
            if let image = image.CIImage {
                return image
            }
            return nil
        }
        guard let inputImage = inputImageForImage(self), outputImage = closure(inputImage) else {
            return nil
        }
        let imageRef = context.createCGImage(outputImage, fromRect: inputImage.extent)
        return UIImage(CGImage: imageRef, scale: self.scale, orientation: self.imageOrientation)
    }

    func applyFilter(filter: CIFilter?, context: CIContext = sharedCIContext) -> UIImage? {
        guard let filter = filter else {
            return nil
        }
        return applyFilter(context: context) {
            filter.setValue($0, forKey: kCIInputImageKey)
            return filter.outputImage
        }
    }
}
```

Now lets create `CIFilter` and use our extension to apply it:

```swift
let filter = CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : 10.0])
let processedImage = image.applyFilter(filter)
```

# Core Image in Nuke

Here's an example of a blur filter that implements Nuke's `Processing` protocol and uses our new extensions:

```swift
/// Blurs image using CIGaussianBlur filter.
struct GaussianBlur: Processing { 
    private let radius: Int

    /// Initializes the receiver with a blur radius.
    init(radius: Int = 8) {
        self.radius = radius
    }

    /// Applies CIGaussianBlur filter to the image.
    func process(image: UIImage) -> UIImage? {
        return image.applyFilter(CIFilter(name: "CIGaussianBlur", withInputParameters: ["inputRadius" : radius]))
    }

    /// Compares two filters based on their radius.
    func ==(lhs: GaussianBlur, rhs: GaussianBlur) -> Bool {
        return lhs.radius == rhs.radius
    }
}
```

# Performance Considerations

- Chaining multiple `CIFilter` objects is much more efficient then using `ProcessorComposition` to combine multiple instances of `CoreImageFilter` class.
- Don’t create a `CIContext` object every time you render.

# References

1. [Core Image Programming Guide](https://developer.apple.com/library/ios/documentation/GraphicsImaging/Conceptual/CoreImaging/ci_intro/ci_intro.html)
2. [Core Image Filter Reference](https://developer.apple.com/library/prerelease/ios/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html)
3. [Core Image Tutorial: Getting Started](http://www.raywenderlich.com/76285/beginning-core-image-swift)
4. [WWDC 2014 Session 514 - Advances in Core Image](http://asciiwwdc.com/2014/sessions/514)
5. [Core Image Shop](https://github.com/rFlex/CoreImageShop) - sample project that lets you experiment with Core Image filters
