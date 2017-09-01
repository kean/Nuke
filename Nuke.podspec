Pod::Spec.new do |s|
    s.name             = 'Nuke'
    s.version          = '5.2'
    s.summary          = 'A powerful image loading and caching framework'
    s.description  = <<-EOS
    A powerful image loading and caching framework which allows for hassle-free image loading in your app - often in one line of code.

    Nuke pulls together stable, mature libraries from Swift ecosystem into simple, lightweight package that lets you focus on getting things done.
    EOS

    s.homepage         = 'https://github.com/kean/Nuke'
    s.license          = 'MIT'
    s.author           = 'Alexander Grebenyuk'
    s.social_media_url = 'https://twitter.com/a_grebenyuk'
    s.source           = { :git => 'https://github.com/kean/Nuke.git', :tag => s.version.to_s }

    s.ios.deployment_target = '9.0'
    s.watchos.deployment_target = '2.0'
    s.osx.deployment_target = '10.11'
    s.tvos.deployment_target = '9.0'

    s.source_files  = 'Sources/**/*'
end
