#!/bin/sh

# -L to enable redirects
echo "Installing SwiftLint by downloading a pre-compiled binary"
curl -L 'https://github.com/realm/SwiftLint/releases/download/0.39.1/portable_swiftlint.zip' -o swiftlint.zip
mkdir temp
unzip swiftlint.zip -d temp
rm -f swiftlint.zip
