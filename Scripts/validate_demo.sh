#!/bin/sh

cd Demo

xcodebuild -workspace NukeDemo.xcworkspace -scheme NukeDemo -destination  "OS=13.0,name=iPhone 11" | xcpretty
