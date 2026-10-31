#!/bin/bash
set -o pipefail

# Usage: test-one.sh <test> [scheme] [platform]
#   <test>      A suite or a test: ImageRequestTests, ImageRequestTests/testInit.
#               Several, separated by spaces, if quoted.
#   [scheme]    Nuke (default), NukeUI, NukeExtensions, NukeVideo,
#               NukeThreadSafetyTests, or NukePerformanceTests.
#   [platform]  macOS (default), iOS, or tvOS.
#
# Runs one test and prints how many ran, so that a filter that matched nothing
# can't pass for green: xcodebuild exits 0 on it.
#
# Everything is built into a derived data folder of its own, under .build/. With
# the project open in Xcode, the shared one can hold a stale test bundle, and the
# run reports TEST SUCCEEDED for code it never built.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TESTS="${1:-}"
SCHEME="${2:-Nuke}"
PLATFORM="${3:-macOS}"

if [ -z "$TESTS" ]; then
    sed -n '4,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
    exit 2
fi

case "$SCHEME" in
    Nuke|NukeUI|NukeExtensions|NukeVideo) TARGET="${SCHEME}Tests" ;;
    NukeThreadSafetyTests|NukePerformanceTests) TARGET="$SCHEME" ;;
    *) echo "error: unknown scheme '$SCHEME'" >&2; exit 2 ;;
esac

# The newest simulator, for the same reason ci.sh picks it: SwiftUI's appearance
# callbacks differ on older runtimes, and 8 NukeUI tests fail on iOS 18.
simulator() {
    xcrun simctl list devices available 2>/dev/null | grep -E "^[[:space:]]+$1" | tail -1 \
        | grep -oE '[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}' | head -1
}

case "$PLATFORM" in
    macOS) DEST="platform=macOS" ;;
    iOS)   DEST="platform=iOS Simulator,id=$(simulator 'iPhone [0-9]')" ;;
    tvOS)  DEST="platform=tvOS Simulator,id=$(simulator 'Apple TV')" ;;
    *)     echo "error: unknown platform '$PLATFORM'" >&2; exit 2 ;;
esac

ARGS=()
for test in $TESTS; do
    # Swift Testing names a test by its function, with the parentheses.
    case "$test" in
        */*\(*) ;;
        */*)    test="$test()" ;;
    esac
    ARGS+=("-only-testing:$TARGET/$test")
done

if [ "$SCHEME" = "NukePerformanceTests" ]; then
    # Hosted in an iOS app, so platform=macOS means Mac Catalyst, and has to be
    # told not to sign. The suites only measure anything one at a time.
    ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
fi

DERIVED_DATA="$PROJECT_ROOT/.build/test-one/$SCHEME-$PLATFORM"
LOG="$PROJECT_ROOT/.build/test-one/$SCHEME-$PLATFORM.log"
mkdir -p "$(dirname "$LOG")"

xcodebuild test \
    -project "$PROJECT_ROOT/Nuke.xcodeproj" \
    -scheme "$SCHEME" \
    -destination "$DEST" \
    -derivedDataPath "$DERIVED_DATA" \
    -collect-test-diagnostics never \
    -parallel-testing-enabled NO \
    "${ARGS[@]}" > "$LOG" 2>&1
STATUS=$?

# Swift Testing prints one tally per run, which xcbeautify would drop:
#   "Test run with 3 tests in 1 suite passed after 0.012 seconds."
TALLY=$(grep -E "Test run with [0-9]+ tests?" "$LOG" | tail -1 | sed -E 's/^.*(Test run with)/\1/')
COUNT=$(printf '%s' "$TALLY" | grep -oE "with [0-9]+" | grep -oE "[0-9]+")

grep -E "error:|Test .*\(.*\) (failed|recorded an issue)|Expectation failed" "$LOG" \
    | grep -v "^/.*\.xcresult" | sort -u | head -40

if [ -n "$TALLY" ]; then
    echo "$TALLY"
fi
echo "log: $LOG"

if [ "$STATUS" -ne 0 ]; then
    echo "FAILED: xcodebuild exited with $STATUS" >&2
    exit "$STATUS"
fi
if [ -z "$COUNT" ] || [ "$COUNT" -eq 0 ]; then
    echo "FAILED: no test ran. Check the name: a suite is 'ImageRequestTests', a test is 'ImageRequestTests/testInit'" >&2
    exit 1
fi
