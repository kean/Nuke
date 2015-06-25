//
//  WKInterfaceImageView.swift
//  Nuke
//
//  Created by Daniel Brooks on 6/24/15.
//  Copyright © 2015 Alexander Grebenyuk. All rights reserved.
//

import WatchKit

public class ImageView: WKInterfaceImage {
  public var imageTask: ImageTask?
  public var allowsAnimations = true
  public var savedImage: UIImage? {
    get {
      return self.savedImage
    }
    set {
      self.setImage(newValue)
      self.savedImage = newValue
    }
  }

  public func prepareForReuse() {
    self.savedImage = nil
    self.imageTask?.cancel()
    self.imageTask = nil
  }

  public func setImageWithURL(URL: NSURL) {
    self.setImageWithRequest(ImageRequest(URL: URL))
  }

  public func setImageWithRequest(request: ImageRequest) {
    self.imageTask?.cancel()
    self.imageTask = nil

    let startTime = mach_absolute_time()
    let imageTask = ImageManager.sharedManager().imageTaskWithRequest(request, completionHandler: { [weak self] (response) -> Void in
      self?.imageTaskDidFinishWithImage(response.image, error: response.error, elapsedTime: Double(mach_absolute_time() - startTime))
      return
      })
    imageTask.resume()
  }

  private func imageTaskDidFinishWithImage(image: UIImage?, error: NSError?, elapsedTime: NSTimeInterval) {
      self.savedImage = image
  }
}
