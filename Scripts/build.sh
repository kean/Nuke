#!/bin/sh

scheme="Nuke"

while getopts "d:" opt; do
    case $opt in
        d) destinations+=("$OPTARG");;
        #...
    esac
done
shift $((OPTIND -1))

echo "destinations = ${destinations[@]}"

set -o pipefail
xcodebuild -version

for dest in "${destinations[@]}"; do
	echo "Building for destination: $dest"
	xcodebuild build -scheme $scheme -destination "$dest" | xcpretty;
    if [ $? -ne 0 ]; then
        exit $?
    fi
done

exit $?
