#!/bin/bash

cd $1
if [ ! -d Nuke.xcodeproj ]; then
    echo "Nuke.xcodeproj not found!"
    exit 1
fi

# Copy project to the tmp folder

tmp_path="/tmp/com.github.kean/" 
tmp_proj_path="$tmp_path/xctool/Nuke"

rm -rf $tmp_path
mkdir -p $tmp_proj_path
cp -a . $tmp_proj_path
cd $tmp_proj_path

# Run tests on all available (and supported by Nuke) SDKs

ios_sdks=$(xcodebuild -showsdks | grep -E "iphonesimulator(8|9).*" | awk 'NF>1{print $NF}')
for ((i = 0; i < ${#ios_sdks[@]}; i++))
do
	xctool test -scheme "Nuke iOS" -sdk ${ios_sdks[$i]} -derivedDataPath $tmp_proj_path
done

osx_sdks=$(xcodebuild -showsdks | grep -E "macosx10.(9|10|11)$" | awk 'NF>1{print $NF}')
for ((i = 0; i < ${#osx_sdks[@]}; i++))
do
	xctool test -scheme "Nuke OSX" -sdk ${osx_sdks[$i]} -derivedDataPath $tmp_proj_path
done

# Build watchOS target (tests are not yet available for watchOS platform)

xctool build -scheme "Nuke watchOS"

# Cleanup

rm -rf $tmp_path
