#!/bin/bash

version_file="Nuke/Supporting Files/Info.plist"
current_version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$version_file")"
echo "Building docs for version $current_version"


declare -a arr=("iOS" "OSX" "tvOS" "watchOS")
for i in "${arr[@]}"
do
	platform_lowercase="$( echo "$i" | tr -s  '[:upper:]'  '[:lower:]' )"

jazzy \
  --clean \
  --author kean \
  --author_url https://github.com/kean \
  --github_url https://github.com/kean/Nuke \
  --github-file-prefix "https://github.com/kean/Nuke/tree/$current_version" \
  --module-version "$current_version" \
  --xcodebuild-arguments -scheme,"Nuke $i" \
  --module Nuke \
  --output "docs/$platform_lowercase"

done
