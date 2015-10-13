Pod::Spec.new do |s|
    s.name             = "Nuke"
    s.version          = "0.5.1"
    s.summary          = "Advanced Swift framework for loading and caching images"

    s.homepage         = "https://github.com/kean/Nuke"
    s.license          = "MIT"
    s.author           = "Alexander Grebenyuk"
    s.source           = { :git => "https://github.com/kean/Nuke.git", :tag => s.version.to_s }
    s.social_media_url = "https://twitter.com/a_grebenyuk"

    s.ios.deployment_target = "8.0"
    s.watchos.deployment_target = "2.0"
    s.osx.deployment_target = "10.9"

    s.requires_arc = true

    s.source_files  = "Nuke/Source/Core/**/*"
    s.ios.source_files = "Nuke/Source/UI/**/*"
end
