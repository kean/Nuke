#!/bin/bash
set -euo pipefail

# Usage: publish-docs.sh [output]
#   [output]  The folder to build the site in. .build/docs by default.
#
# Builds the documentation of every module for static hosting, with the layout
# of https://kean-docs.github.io: each module is a folder of its own, and the
# name of the folder is the base path of its pages, as in
# /nukeui/documentation/nukeui/lazyimage.
#
# It stops there, and nothing is pushed or deployed. The site has no versions,
# so what goes there replaces the docs for everyone, including apps on the last
# release: deploy at the tag, with deploy-docs.sh, which builds this and commits it to
# kean-docs/kean-docs.github.io.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

OUTPUT="${1:-$PROJECT_ROOT/.build/docs}"
# A derived data folder of its own: with the project open in Xcode, the shared
# one can hold a stale archive.
DERIVED_DATA="$PROJECT_ROOT/.build/docs-derived-data"
PRODUCTS="$DERIVED_DATA/Build/Products/Debug-iphonesimulator"
MODULES=(Nuke NukeUI NukeVideo NukeExtensions)

mkdir -p "$OUTPUT" "$DERIVED_DATA"

# Runs a step with its output in the log, and stops the script if it fails.
run() {
    local log="$1" step="$2"
    shift 2
    if ! "$@" > "$log" 2>&1; then
        tail -20 "$log" >&2
        echo "error: $step failed, the log is in $log" >&2
        exit 1
    fi
}

# Builds the archive of a module that re-exports Nuke, without Nuke in it.
#
# NukeUI, NukeVideo, and NukeExtensions `@_exported import Nuke`, and the
# symbol graphs the compiler emits for docbuild include every symbol of a
# re-exported module, with no option to leave them out. Their sites had a copy
# of every Nuke page, with no documentation on it, and their links to Nuke
# landed on the copies. swift-symbolgraph-extract has the option, so the module
# is built, its symbol graphs are extracted from the built module, and DocC
# converts those.
build_archive_without_nuke() {
    local module="$1" base_path="$2" archive="$3"
    local graphs="$DERIVED_DATA/symbol-graphs/$module"

    # The simulator rather than macOS, so that the UIKit API is documented.
    run "$DERIVED_DATA/$module.log" "the build of $module" \
        xcodebuild build \
            -project "$PROJECT_ROOT/Nuke.xcodeproj" \
            -scheme "$module" \
            -destination "generic/platform=iOS Simulator" \
            -derivedDataPath "$DERIVED_DATA"

    # The deployment target the module was built for, which the extractor has
    # to match to load it.
    local interface="$PRODUCTS/$module.framework/Modules/$module.swiftmodule/arm64-apple-ios-simulator.swiftinterface"
    local target
    target="$(sed -n 's/^\/\/ swift-module-flags: .*-target \([^ ]*\).*/\1/p' "$interface" 2>/dev/null | head -1)"
    if [ -z "$target" ]; then
        echo "error: no target triple for $module in $interface" >&2
        exit 1
    fi

    # An empty list of the re-exported modules to include: none of them. What
    # the module adds to a Nuke type goes in a symbol graph of its own,
    # $module@Nuke, and DocC shows it under Extended Modules.
    rm -rf "$graphs"
    mkdir -p "$graphs"
    run "$DERIVED_DATA/$module-symbol-graph.log" "the symbol graph extraction of $module" \
        xcrun swift-symbolgraph-extract \
            -module-name "$module" \
            -target "$target" \
            -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
            -F "$PRODUCTS" \
            -I "$PRODUCTS" \
            -minimum-access-level public \
            -emit-extension-block-symbols \
            -experimental-allowed-reexported-modules= \
            -output-dir "$graphs"

    # NukeVideo.docc isn't in the Xcode target, unlike the other catalogs: it
    # curates what NukeVideo adds to Nuke types by the path it has here,
    # Nuke/ImageDecoders/Video, and a docbuild that copies Nuke has no such path.
    rm -rf "$archive"
    mkdir -p "$(dirname "$archive")"
    run "$DERIVED_DATA/$module-docc.log" "the docc conversion of $module" \
        xcrun docc convert "$PROJECT_ROOT/Documentation/$module.docc" \
            --additional-symbol-graph-dir "$graphs" \
            --fallback-display-name "$module" \
            --fallback-bundle-identifier "com.github.kean.$base_path" \
            --hosting-base-path "$base_path" \
            --output-path "$archive"

    # A toolchain that stops reading the empty list as one would bring the
    # copies back without a word.
    if [ -e "$archive/data/documentation/$base_path/imagepipeline.json" ]; then
        echo "error: the archive of $module documents ImagePipeline, which is a Nuke symbol" >&2
        exit 1
    fi
}

for module in "${MODULES[@]}"; do
    base_path="$(echo "$module" | tr '[:upper:]' '[:lower:]')"

    echo "▸ $module"
    if [ "$module" = Nuke ]; then
        run "$DERIVED_DATA/$module.log" "the docbuild of $module" \
            xcodebuild docbuild \
                -project "$PROJECT_ROOT/Nuke.xcodeproj" \
                -scheme "$module" \
                -destination "generic/platform=iOS Simulator" \
                -derivedDataPath "$DERIVED_DATA"
        archive="$(find "$PRODUCTS" -maxdepth 1 -type d -name "$module.doccarchive" | head -1)"
    else
        archive="$DERIVED_DATA/archives/$module.doccarchive"
        build_archive_without_nuke "$module" "$base_path" "$archive"
    fi
    if [ ! -d "$archive" ]; then
        echo "error: no archive for $module in $DERIVED_DATA" >&2
        exit 1
    fi

    rm -rf "${OUTPUT:?}/$base_path"
    xcrun docc process-archive transform-for-static-hosting "$archive" \
        --hosting-base-path "$base_path" \
        --output-path "$OUTPUT/$base_path"

    if [ ! -f "$OUTPUT/$base_path/documentation/$base_path/index.html" ]; then
        echo "error: no landing page in $OUTPUT/$base_path" >&2
        exit 1
    fi
done

echo
echo "The site is in $OUTPUT, and nothing was deployed. To preview it:"
echo "  python3 -m http.server --directory \"$OUTPUT\" 8000"
echo "  open http://localhost:8000/nuke/documentation/nuke/"
