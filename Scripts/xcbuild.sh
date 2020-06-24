#!/bin/sh

xcodebuild archive -scheme Nuke -archivePath "./.build/xcbuild/ios.xcarchive" -sdk iphoneos SKIP_INSTALL=NO
xcodebuild archive -scheme Nuke -archivePath "./.build/xcbuild/ios-sim.xcarchive" -sdk iphonesimulator SKIP_INSTALL=NO
xcodebuild archive -scheme Nuke -archivePath "./.build/xcbuild/macos.xcarchive" -sdk macosx SKIP_INSTALL=NO
xcodebuild archive -scheme Nuke -archivePath "./.build/xcbuild/tvos.xcarchive" -sdk appletvos SKIP_INSTALL=NO
xcodebuild archive -scheme Nuke -archivePath "./.build/xcbuild/tvos-sim.xcarchive" -sdk appletvsimulator SKIP_INSTALL=NO
xcodebuild archive -scheme Nuke -archivePath "./.build/xcbuild/watchos.xcarchive" -sdk watchos SKIP_INSTALL=NO
xcodebuild archive -scheme Nuke -archivePath "./.build/xcbuild/watchos-sim.xcarchive" -sdk watchsimulator SKIP_INSTALL=NO

xcodebuild -create-xcframework \
    -output "./.build/xcbuild/Nuke.xcframework" \
    -framework "./.build/xcbuild/ios.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "./.build/xcbuild/ios-sim.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "./.build/xcbuild/macos.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "./.build/xcbuild/tvos.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "./.build/xcbuild/tvos-sim.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "./.build/xcbuild/watchos.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "./.build/xcbuild/watchos-sim.xcarchive/Products/Library/Frameworks/Nuke.framework"
