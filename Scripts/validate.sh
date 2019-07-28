#!/bin/sh

# 1. SwiftLint
###############################################################

# Install SwiftLint
#
# Unfortunately, CocoaPods seem to be the only relatively
# straighforward way to install a specific SwiftLint version

gem install cocoapods -v 1.7.3

echo "
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '10.0'

target 'Nuke' do
	pod 'SwiftLint', '0.30.0'
end
" >> Podfile

pod install

# Perform the actual validation
Pods/SwiftLint/swiftlint lint --strict