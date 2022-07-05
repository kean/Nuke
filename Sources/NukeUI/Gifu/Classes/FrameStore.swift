#if os(iOS) || os(tvOS)
import ImageIO
import UIKit

/// Responsible for storing and updating the frames of a single GIF.
class FrameStore {

  /// Total duration of one animation loop
  var loopDuration: TimeInterval = 0

  /// Flag indicating if number of loops has been reached
  var isFinished: Bool = false

  /// Desired number of loops, <= 0 for infinite loop
  let loopCount: Int

  /// Index of current loop
  var currentLoop = 0

  /// Maximum duration to increment the frame timer with.
  let maxTimeStep = 1.0

  /// An array of animated frames from a single GIF image.
  var animatedFrames = [AnimatedFrame]()

  /// The target size for all frames.
  let size: CGSize

  /// The content mode to use when resizing.
  let contentMode: UIView.ContentMode

  /// Maximum number of frames to load at once
  let bufferFrameCount: Int

  /// The total number of frames in the GIF.
  var frameCount = 0

  /// A reference to the original image source.
  var imageSource: CGImageSource

  /// The index of the current GIF frame.
  var currentFrameIndex = 0 {
    didSet {
      previousFrameIndex = oldValue
    }
  }

  /// The index of the previous GIF frame.
  var previousFrameIndex = 0 {
    didSet {
      preloadFrameQueue.async {
        self.updatePreloadedFrames()
      }
    }
  }

  /// Time elapsed since the last frame change. Used to determine when the frame should be updated.
  var timeSinceLastFrameChange: TimeInterval = 0.0

  /// Specifies whether GIF frames should be resized.
  var shouldResizeFrames = true
  
  /// Dispatch queue used for preloading images.
  private lazy var preloadFrameQueue: DispatchQueue = {
    return DispatchQueue(label: "co.kaishin.Gifu.preloadQueue")
  }()

  /// The current image frame to show.
  var currentFrameImage: UIImage? {
    return frame(at: currentFrameIndex)
  }

  /// The current frame duration
  var currentFrameDuration: TimeInterval {
    return duration(at: currentFrameIndex)
  }

  /// Is this image animatable?
  var isAnimatable: Bool {
    return imageSource.isAnimatedGIF
  }

  private let lock = NSLock()

  /// Creates an animator instance from raw GIF image data and an `Animatable` delegate.
  ///
  /// - parameter data: The raw GIF image data.
  /// - parameter delegate: An `Animatable` delegate.
  init(data: Data, size: CGSize, contentMode: UIView.ContentMode, framePreloadCount: Int, loopCount: Int) {
    let options = [String(kCGImageSourceShouldCache): kCFBooleanFalse] as CFDictionary
    self.imageSource = CGImageSourceCreateWithData(data as CFData, options) ?? CGImageSourceCreateIncremental(options)
    self.size = size
    self.contentMode = contentMode
    self.bufferFrameCount = framePreloadCount
    self.loopCount = loopCount
  }

  // MARK: - Frames
  /// Loads the frames from an image source, resizes them, then caches them in `animatedFrames`.
  func prepareFrames(_ completionHandler: (() -> Void)? = nil) {
    frameCount = Int(CGImageSourceGetCount(imageSource))
    lock.lock()
    animatedFrames.reserveCapacity(frameCount)
    lock.unlock()
    preloadFrameQueue.async {
      self.setupAnimatedFrames()
      completionHandler?()
    }
  }

  /// Returns the frame at a particular index.
  ///
  /// - parameter index: The index of the frame.
  /// - returns: An optional image at a given frame.
  func frame(at index: Int) -> UIImage? {
    lock.lock()
    defer { lock.unlock() }
    return animatedFrames[safe: index]?.image
  }

  /// Returns the duration at a particular index.
  ///
  /// - parameter index: The index of the duration.
  /// - returns: The duration of the given frame.
  func duration(at index: Int) -> TimeInterval {
    lock.lock()
    defer { lock.unlock() }
    return animatedFrames[safe: index]?.duration ?? TimeInterval.infinity
  }

  /// Checks whether the frame should be changed and calls a handler with the results.
  ///
  /// - parameter duration: A `CFTimeInterval` value that will be used to determine whether frame should be changed.
  /// - parameter handler: A function that takes a `Bool` and returns nothing. It will be called with the frame change result.
  func shouldChangeFrame(with duration: CFTimeInterval, handler: (Bool) -> Void) {
    incrementTimeSinceLastFrameChange(with: duration)

    if currentFrameDuration > timeSinceLastFrameChange {
      handler(false)
    } else {
      resetTimeSinceLastFrameChange()
      incrementCurrentFrameIndex()
      handler(true)
    }
  }
}

private extension FrameStore {
  /// Whether preloading is needed or not.
  var preloadingIsNeeded: Bool {
    return bufferFrameCount < frameCount - 1
  }

  /// Optionally loads a single frame from an image source, resizes it if required, then returns an `UIImage`.
  ///
  /// - parameter index: The index of the frame to load.
  /// - returns: An optional `UIImage` instance.
  func loadFrame(at index: Int) -> UIImage? {
    guard let imageRef = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else { return nil }
    let image = UIImage(cgImage: imageRef)
    let scaledImage: UIImage?

    if shouldResizeFrames {
      switch self.contentMode {
      case .scaleAspectFit: scaledImage = image.constrained(by: size)
      case .scaleAspectFill: scaledImage = image.filling(size: size)
      default: scaledImage = image.resized(to: size)
      }
    } else {
      scaledImage = image
    }

    return scaledImage
  }

  /// Updates the frames by preloading new ones and replacing the previous frame with a placeholder.
  func updatePreloadedFrames() {
    if !preloadingIsNeeded { return }
    lock.lock()
    animatedFrames[previousFrameIndex] = animatedFrames[previousFrameIndex].placeholderFrame
    lock.unlock()

    for index in preloadIndexes(withStartingIndex: currentFrameIndex) {
      loadFrameAtIndexIfNeeded(index)
    }
  }

  func loadFrameAtIndexIfNeeded(_ index: Int) {
    let frame: AnimatedFrame
    lock.lock()
    frame = animatedFrames[index]
    lock.unlock()
    if !frame.isPlaceholder { return }
    let loadedFrame = frame.makeAnimatedFrame(with: loadFrame(at: index))
    lock.lock()
    animatedFrames[index] = loadedFrame
    lock.unlock()
  }

  /// Increments the `timeSinceLastFrameChange` property with a given duration.
  ///
  /// - parameter duration: An `NSTimeInterval` value to increment the `timeSinceLastFrameChange` property with.
  func incrementTimeSinceLastFrameChange(with duration: TimeInterval) {
    timeSinceLastFrameChange += min(maxTimeStep, duration)
  }

  /// Ensures that `timeSinceLastFrameChange` remains accurate after each frame change by subtracting the `currentFrameDuration`.
  func resetTimeSinceLastFrameChange() {
    timeSinceLastFrameChange -= currentFrameDuration
  }

  /// Increments the `currentFrameIndex` property.
  func incrementCurrentFrameIndex() {
    currentFrameIndex = increment(frameIndex: currentFrameIndex)
    if isLastLoop(loopIndex: currentLoop) && isLastFrame(frameIndex: currentFrameIndex) {
        isFinished = true
    } else if currentFrameIndex == 0 {
        currentLoop = currentLoop + 1
    }
  }

  /// Increments a given frame index, taking into account the `frameCount` and looping when necessary.
  ///
  /// - parameter index: The `Int` value to increment.
  /// - parameter byValue: The `Int` value to increment with.
  /// - returns: A new `Int` value.
  func increment(frameIndex: Int, by value: Int = 1) -> Int {
    return (frameIndex + value) % frameCount
  }

  /// Indicates if current frame is the last one.
  /// - parameter frameIndex: Index of current frame.
  /// - returns: True if current frame is the last one.
  func isLastFrame(frameIndex: Int) -> Bool {
    return frameIndex == frameCount - 1
  }

  /// Indicates if current loop is the last one. Always false for infinite loops.
  /// - parameter loopIndex: Index of current loop.
  /// - returns: True if current loop is the last one.
  func isLastLoop(loopIndex: Int) -> Bool {
    return loopIndex == loopCount - 1
  }

  /// Returns the indexes of the frames to preload based on a starting frame index.
  ///
  /// - parameter index: Starting index.
  /// - returns: An array of indexes to preload.
  func preloadIndexes(withStartingIndex index: Int) -> [Int] {
    let nextIndex = increment(frameIndex: index)
    let lastIndex = increment(frameIndex: index, by: bufferFrameCount)

    if lastIndex >= nextIndex {
      return [Int](nextIndex...lastIndex)
    } else {
      return [Int](nextIndex..<frameCount) + [Int](0...lastIndex)
    }
  }

  func setupAnimatedFrames() {
      resetAnimatedFrames()

      var duration: TimeInterval = 0

      (0..<frameCount).forEach { index in
          lock.lock()
          let frameDuration = CGImageFrameDuration(with: imageSource, atIndex: index)
          duration += min(frameDuration, maxTimeStep)
          animatedFrames += [AnimatedFrame(image: nil, duration: frameDuration)]
          lock.unlock()

          if index > bufferFrameCount { return }
          loadFrameAtIndexIfNeeded(index)
      }

      self.loopDuration = duration
  }

  /// Reset animated frames.
  func resetAnimatedFrames() {
    animatedFrames = []
  }
}
#endif
