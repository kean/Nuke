#!/bin/sh

scheme="Nuke"
platform=$1
xcode=$2

set -o pipefail
xcodebuild -version

function build() {
	for destination in "$@"; do
		xcodebuild build -scheme $scheme -destination "$destination" | xcpretty;
	done
}

function test() {
	xcodebuild build-for-testing -scheme $scheme -destination "$1" | xcpretty;

	for destination in "$@"; do
		# passing multiple destinations to `test` command results in Travis hanging
		xcodebuild test-without-building -scheme $scheme -destination "$destination" | xcpretty;
	done
}

if [ $platform == "iOS" ]; then

	if [ $xcode == "xcode11" ]; then
		test "OS=13.0,name=iPhone Xs"
	else
		test "OS=12.2,name=iPhone X" "OS=11.4,name=iPhone X" "OS=10.3.1,name=iPhone SE"
	fi
fi

if [ $platform == "macOS" ]; then
	test "arch=x86_64"
fi

if [ $platform == "watchOS" ]; then
	build "OS=4.2,name=Apple Watch - 42mm" "OS=3.2,name=Apple Watch - 42mm"
fi

if [ $platform == "tvOS" ]; then
	test "OS=12.2,name=Apple TV 4K" "OS=11.3,name=Apple TV 4K"
fi