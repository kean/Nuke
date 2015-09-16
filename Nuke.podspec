Pod::Spec.new do |s|
  s.name             = "Nuke"
  s.version          = "0.1.0"
  s.summary          = "Advanced framework for loading images"

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!  
  s.description      = <<-DESC
                       DESC

  s.homepage         = "https://github.com/kean/Nuke"
  s.license          = 'MIT'
  s.author           = { "kean" => "grebenyuk.alexander@gmail.com" }
  s.source           = { :git => "https://github.com/kean/Nuke.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/a_grebenyuk'

  s.platform     = :ios, '8.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes/**/*'

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
