#!/bin/sh

if which swiftlint >/dev/null; then
  swiftlint
else
  echo "SwiftLint not installed"
fi
