Pod::Spec.new do |s|
    s.name             = "Nuke"
    s.version          = "1.0.0"
    s.summary          = "Advanced Swift framework for loading images"
    s.description  = <<-EOS
    Advanced pure Swift framework for loading, caching, processing, displaying and preheating images.

    Has full featured UI extensions, support for image filters, optional Alamofire and FLAnimatedImage plugins and [more](https://github.com/kean/Nuke).
    EOS

    s.homepage         = "https://github.com/kean/Nuke"
    s.license          = "MIT"
    s.author           = "Alexander Grebenyuk"
    s.social_media_url = "https://twitter.com/a_grebenyuk"
    s.source           = { :git => "https://github.com/kean/Nuke.git", :tag => s.version.to_s }

    s.ios.deployment_target = "8.0"
    s.watchos.deployment_target = "2.0"
    s.osx.deployment_target = "10.9"
    s.tvos.deployment_target = "9.0"

    s.source_files  = "Nuke/Source/Core/**/*"
    s.ios.source_files = "Nuke/Source/UI/**/*"
    s.tvos.source_files = "Nuke/Source/UI/**/*"
    s.osx.source_files = "Nuke/Source/UI/{ImageLoadingView,ImageLoadingViewExtensions,ImageViewLoadingController}.swift"
end
