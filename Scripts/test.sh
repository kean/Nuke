#!/bin/sh

scheme="Nuke"
platform=$1
xcode=$2

set -o pipefail
xcodebuild -version

if [ $platform == "iOS" ]; then

	if [ $xcode == "xcode11" ]; then
		xcodebuild test -scheme $scheme -destination "OS=13.0,name=iPhone Xs" | xcpretty;
	else
		xcodebuild build-for-testing -scheme $scheme -destination "OS=12.2,name=iPhone X" | xcpretty;

		# passing multiple destinations to `test` command results in Travis hanging
		xcodebuild test-without-building -scheme $scheme -destination "OS=12.2,name=iPhone X" | xcpretty;
		xcodebuild test-without-building -scheme $scheme -destination "OS=11.4,name=iPhone X" | xcpretty;
		xcodebuild test-without-building -scheme $scheme -destination "OS=10.3.1,name=iPhone SE" | xcpretty;
	fi
fi

if [ $platform == "macOS" ]; then
	xcodebuild test -scheme $scheme -destination "arch=x86_64" | xcpretty;
fi

if [ $platform == "watchOS" ]; then
	xcodebuild build -scheme $scheme -destination "OS=4.2,name=Apple Watch - 42mm" | xcpretty;
	xcodebuild build -scheme $scheme -destination "OS=3.2,name=Apple Watch - 42mm" | xcpretty;
fi

if [ $platform == "tvOS" ]; then
	xcodebuild build-for-testing -scheme $scheme -destination "OS=12.2,name=Apple TV 4K" | xcpretty;

	# passing multiple destinations to `test` command results in Travis hanging
	xcodebuild test-without-building -scheme $scheme -destination "OS=12.2,name=Apple TV 4K" | xcpretty;
	xcodebuild test-without-building -scheme $scheme -destination "OS=11.3,name=Apple TV 4K" | xcpretty;
fi

exit $?