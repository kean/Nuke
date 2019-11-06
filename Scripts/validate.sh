#!/bin/sh

# Install SwiftLint

# -L to enable redirects
curl -L 'https://github.com/realm/SwiftLint/releases/download/0.36.0/portable_swiftlint.zip' -o swiftlint.zip
mkdir temp
unzip swiftlint.zip -d temp
rm -f swiftlint.zip

# Perform the actual validation

./temp/swiftlint lint --strict
rm -rf temp
