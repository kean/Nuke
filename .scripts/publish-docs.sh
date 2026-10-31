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
# release: deploy at the tag. To deploy, copy the folders over the ones with the
# same names in kean-docs/kean-docs.github.io, and commit there.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

OUTPUT="${1:-$PROJECT_ROOT/.build/docs}"
# A derived data folder of its own: with the project open in Xcode, the shared
# one can hold a stale archive.
DERIVED_DATA="$PROJECT_ROOT/.build/docs-derived-data"
MODULES=(Nuke NukeUI NukeVideo NukeExtensions)

mkdir -p "$OUTPUT"

for module in "${MODULES[@]}"; do
    base_path="$(echo "$module" | tr '[:upper:]' '[:lower:]')"
    log="$DERIVED_DATA/$module.log"
    mkdir -p "$DERIVED_DATA"

    echo "▸ $module"
    # The simulator rather than macOS, so that the UIKit API is documented.
    if ! xcodebuild docbuild \
        -project "$PROJECT_ROOT/Nuke.xcodeproj" \
        -scheme "$module" \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$DERIVED_DATA" > "$log" 2>&1; then
        tail -20 "$log" >&2
        echo "error: the docbuild of $module failed, the log is in $log" >&2
        exit 1
    fi

    archive="$(find "$DERIVED_DATA/Build/Products" -maxdepth 2 -type d -name "$module.doccarchive" | head -1)"
    if [ -z "$archive" ]; then
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
