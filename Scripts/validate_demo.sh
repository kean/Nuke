#!/bin/sh

gem install cocoapods -v 1.7.3
cd Demo
pod install

xcodebuild -workspace NukeDemo.xcworkspace -scheme NukeDemo -destination  "OS=13.0,name=iPhone Xs" | xcpretty