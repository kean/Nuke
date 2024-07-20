ROOT="./.build/xcframeworks"

rm -rf $ROOT

for SDK in iphoneos iphonesimulator macosx appletvos appletvsimulator watchos watchsimulator
do
xcodebuild archive \
    -scheme NukeUI \
    -archivePath "$ROOT/nuke-$SDK.xcarchive" \
    -sdk $SDK \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    DEBUG_INFORMATION_FORMAT=DWARF
done

xcodebuild -create-xcframework \
    -framework "$ROOT/nuke-iphoneos.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "$ROOT/nuke-iphonesimulator.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -output "$ROOT/Nuke.xcframework"

xcodebuild -create-xcframework \
    -framework "$ROOT/nuke-iphoneos.xcarchive/Products/Library/Frameworks/NukeUI.framework" \
    -framework "$ROOT/nuke-iphonesimulator.xcarchive/Products/Library/Frameworks/NukeUI.framework" \
    -output "$ROOT/NukeUI.xcframework"

cd $ROOT
zip -r -X nuke-xcframeworks-ios.zip *.xcframework
rm -rf *.xcframework
cd -

xcodebuild -create-xcframework \
    -framework "$ROOT/nuke-iphoneos.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "$ROOT/nuke-iphonesimulator.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "$ROOT/nuke-macosx.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "$ROOT/nuke-appletvos.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "$ROOT/nuke-appletvsimulator.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "$ROOT/nuke-watchos.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -framework "$ROOT/nuke-watchsimulator.xcarchive/Products/Library/Frameworks/Nuke.framework" \
    -output "$ROOT/Nuke.xcframework"

xcodebuild -create-xcframework \
    -framework "$ROOT/nuke-iphoneos.xcarchive/Products/Library/Frameworks/NukeUI.framework" \
    -framework "$ROOT/nuke-iphonesimulator.xcarchive/Products/Library/Frameworks/NukeUI.framework" \
    -framework "$ROOT/nuke-macosx.xcarchive/Products/Library/Frameworks/NukeUI.framework" \
    -framework "$ROOT/nuke-appletvos.xcarchive/Products/Library/Frameworks/NukeUI.framework" \
    -framework "$ROOT/nuke-appletvsimulator.xcarchive/Products/Library/Frameworks/NukeUI.framework" \
    -framework "$ROOT/nuke-watchos.xcarchive/Products/Library/Frameworks/NukeUI.framework" \
    -framework "$ROOT/nuke-watchsimulator.xcarchive/Products/Library/Frameworks/NukeUI.framework" \
    -output "$ROOT/NukeUI.xcframework"

cd $ROOT
zip -r -X nuke-xcframeworks-all-platforms.zip *.xcframework
rm -rf *.xcframework
cd -

mv $ROOT/*.zip ./
