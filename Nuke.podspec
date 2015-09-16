Pod::Spec.new do |s|
  s.name             = "Nuke"
  s.version          = "0.1.0"
  s.summary          = "Advanced Swift framework for loading and caching images"

  s.homepage         = "https://github.com/kean/Nuke"
  s.license          = 'MIT'
  s.author           = "Alexander Grebenyuk"
  s.source           = { :git => "https://github.com/kean/Nuke.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/a_grebenyuk'

  s.platform     = :ios, '8.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes/**/*'
end
