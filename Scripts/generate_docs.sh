#!/bin/sh

version=$1

swift doc generate ./Sources \
    --module-name Nuke \
    --format html \
    --base-url "https://kean-org.github.io/docs/nuke/reference/$version"
