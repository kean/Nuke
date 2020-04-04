#!/bin/sh

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


set -o pipefail
xcodebuild -version


xcodebuild build-for-testing -scheme "$scheme" -destination "${destinations[0]}" | xcpretty;
if [ $? -ne 0 ]; then
    exit $?
fi

for destination in "${destinations[@]}"; do
	echo "\nRunning tests for destination: $destination"

	# passing multiple destinations to `test` command results in Travis hanging
	xcodebuild test-without-building -scheme "$scheme" -destination "$destination" | xcpretty;

    if [ $? -ne 0 ]; then
        exit $?
    fi
done

exit $?
