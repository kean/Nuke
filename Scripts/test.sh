#!/bin/sh

set -eo pipefail

scheme="Nuke"

while getopts "s:d:" opt; do
    case $opt in
    	s) scheme=${OPTARG};;
        d) destinations+=("$OPTARG");;
        #...
    esac
done
shift $((OPTIND -1))

echo "scheme = ${scheme}"
echo "destinations = ${destinations[@]}"

xcodebuild -version

xcodebuild build-for-testing -scheme "$scheme" -destination "${destinations[0]}" | xcpretty

for destination in "${destinations[@]}";
do
	echo "\nRunning tests for destination: $destination"
	xcodebuild test-without-building -scheme "$scheme" -destination "$destination" | xcpretty --test
done
