#!/bin/bash
set -o pipefail

# Usage: ci.sh [--list | --group <group> | <job-id>]
#   (no args)          Run every job
#   --list             Print all job IDs and groups
#   --group <group>    Run every job in a CI group (this is what GitHub Actions calls)
#   <job-id>           Run a single job (see --list)
#
# This script is the single source of truth for the CI matrix. The GitHub
# workflow does nothing except invoke `--group` for each of its five macOS jobs,
# so `make ci` locally runs exactly what CI runs.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_ROOT/Nuke.xcodeproj"
OUTPUT_DIR="$PROJECT_ROOT/.build/ci"

# ── Job matrix ────────────────────────────────────────────────────────────────
#
# id | group | action | scheme | platform
#
# Groups are balanced so that no single GitHub job dominates the critical path.
# GitHub Free allows only 5 concurrent macOS runners, so there are exactly 5.

JOBS=(
    "test-nuke-ios|ios-core|test|Nuke|iOS"

    "test-nukeui-ios|ios-ui|test|NukeUI|iOS"
    "test-nukeextensions-ios|ios-ui|test|NukeExtensions|iOS"

    "test-nuke-tvos|tvos|test|Nuke|tvOS"
    "test-nukeui-tvos|tvos|test|NukeUI|tvOS"
    "test-nukeextensions-tvos|tvos|test|NukeExtensions|tvOS"

    "test-nuke-macos|macos|test|Nuke|macOS"
    "test-nukeui-macos|macos|test|NukeUI|macOS"
    "test-nukeextensions-macos|macos|test|NukeExtensions|macOS"

    "build-nuke-watchos|platforms|build|Nuke|watchOS"
    "build-nukeui-watchos|platforms|build|NukeUI|watchOS"
    "build-nukeextensions-watchos|platforms|build|NukeExtensions|watchOS"
    "build-nukevideo-watchos|platforms|build|NukeVideo|watchOS"
    "build-nuke-visionos|platforms|build|Nuke|visionOS"
    "build-nukeui-visionos|platforms|build|NukeUI|visionOS"
    "build-nukeextensions-visionos|platforms|build|NukeExtensions|visionOS"
    "build-nukevideo-visionos|platforms|build|NukeVideo|visionOS"
    "build-nukevideo-ios|platforms|build|NukeVideo|iOS"
    "build-nukevideo-macos|platforms|build|NukeVideo|macOS"
    "build-nukevideo-tvos|platforms|build|NukeVideo|tvOS"
    "spm-build|platforms|spm|Package|SPM"

    "lint|lint|lint|SwiftLint|—"
)

# Note: `GROUPS` is a read-only bash builtin — this must not be named that.
CI_GROUPS=(ios-core ios-ui tvos macos platforms lint)

# ── Parse arguments ───────────────────────────────────────────────────────────
LIST_MODE=false
JOB_FILTER=""
GROUP_FILTER=""
case "${1:-}" in
    --list)  LIST_MODE=true ;;
    --group) GROUP_FILTER="${2:-}"
             if [ -z "$GROUP_FILTER" ]; then
                 echo "error: --group requires a group name" >&2; exit 2
             fi ;;
    "")      ;;
    -*)      echo "error: unknown option '$1'" >&2; exit 2 ;;
    *)       JOB_FILTER="$1" ;;
esac

# ── Colors ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'
    YELLOW=$'\033[0;33m'
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    RED=''; GREEN=''; BLUE=''; YELLOW=''; BOLD=''; DIM=''; RESET=''
fi

# GitHub Actions renders collapsible groups from ::group:: markers.
_IS_CI="${GITHUB_ACTIONS:-false}"

# ── Result tracking ───────────────────────────────────────────────────────────
JOB_NAMES=()
JOB_ACTIONS=()
JOB_STATUSES=()
JOB_LOG_PATHS=()
JOB_XCRESULT_PATHS=()
JOB_TEST_SUMMARIES=()
JOB_DURATIONS=()

# ── Helpers ───────────────────────────────────────────────────────────────────
sanitize_name() {
    echo "$1" | tr ' /()·' '_____' | tr -cd '[:alnum:]_-'
}

format_duration() {
    local secs="$1"
    if [ "$secs" -ge 60 ]; then
        printf "%dm %ds" $(( secs / 60 )) $(( secs % 60 ))
    else
        printf "%ds" "$secs"
    fi
}

# Swift Testing prints one authoritative tally per attempt:
#   "Test run with 940 tests in 74 suites passed after 1.463 seconds."
# Take the last one, because -retry-tests-on-failure re-runs the whole suite and
# summing every "Test x() passed" line across attempts double-counts. XCTest's
# "Executed N tests, with M failures" line is the fallback for targets still on it.
parse_test_results() {
    local log_file="$1" job_status="$2"
    local total failed line

    line=$(grep -E "Test run with [0-9]+ test" "$log_file" 2>/dev/null | tail -1)
    if [ -n "$line" ]; then
        total=$(echo "$line" | grep -oE "with [0-9]+ test" | grep -oE "[0-9]+")
    else
        line=$(grep -E "Executed [0-9]+ test" "$log_file" 2>/dev/null | tail -1)
        [ -z "$line" ] && { echo "—"; return; }
        total=$(echo "$line" | grep -oE "[0-9]+ test" | grep -oE "[0-9]+")
    fi
    total=${total:-0}
    [ "$total" -eq 0 ] && { echo "—"; return; }

    # Individual failure lines span every attempt, which is what we want: if the
    # job still passed, each one was rescued by a retry, i.e. a flaky test.
    failed=$(grep -cE "Test .*\(.*\) failed after" "$log_file" 2>/dev/null | tr -d ' ')
    failed=${failed:-0}
    if [ "$failed" -eq 0 ]; then
        failed=$(echo "$line" | grep -oE "with [0-9]+ failure" | grep -oE "[0-9]+")
        failed=${failed:-0}
    fi

    if [ "$failed" -eq 0 ]; then
        echo "$total run · $total ✓"
    elif [ "$job_status" -eq 0 ]; then
        # xcodebuild exited 0 despite failures, so -retry-tests-on-failure
        # rescued them. Surface it — a silent retry is a hidden flaky test.
        echo "$total run · $((total - failed)) ✓ · $failed flaky ⚠️"
    else
        echo "$total run · $((total - failed)) ✓ · $failed ✗"
    fi
}

# Pick the newest available simulator matching a name pattern. Resolving at
# runtime is what keeps this working across runner-image updates — pinning
# "OS=26.4.1" is what forced the repeated ci.yml churn in the past.
find_simulator() {
    xcrun simctl list devices available 2>/dev/null \
        | grep -E "^\s+${1}" \
        | tail -1 \
        | sed 's/^[[:space:]]*//' \
        | sed 's/ ([0-9A-Fa-f]\{8\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{12\}).*//'
}

# Booting the simulator up front rather than letting xcodebuild do it lazily
# avoids the first-test-run flakiness that commit a439c17a worked around.
ensure_booted() {
    local name="$1"
    xcrun simctl boot "$name" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$name" -b >/dev/null 2>&1 || true
}

_IOS_SIM=""; _TV_SIM=""
resolve_simulator() {
    case "$1" in
        iOS)
            if [ -z "$_IOS_SIM" ]; then
                _IOS_SIM=$(find_simulator "iPhone [0-9]")
                _IOS_SIM=${_IOS_SIM:-"iPhone 17 Pro"}
                ensure_booted "$_IOS_SIM"
            fi
            echo "$_IOS_SIM" ;;
        tvOS)
            if [ -z "$_TV_SIM" ]; then
                _TV_SIM=$(find_simulator "Apple TV")
                _TV_SIM=${_TV_SIM:-"Apple TV"}
                ensure_booted "$_TV_SIM"
            fi
            echo "$_TV_SIM" ;;
    esac
}

# Tests need a concrete simulator; compile-only jobs use a generic destination
# so they never pay the simulator boot cost.
destination_for() {
    local action="$1" platform="$2"
    if [ "$action" = "build" ]; then
        echo "generic/platform=$platform"
        return
    fi
    case "$platform" in
        iOS)   echo "platform=iOS Simulator,name=$(resolve_simulator iOS)" ;;
        tvOS)  echo "platform=tvOS Simulator,name=$(resolve_simulator tvOS)" ;;
        macOS) echo "platform=macOS" ;;
        *)     echo "generic/platform=$platform" ;;
    esac
}

# xcbeautify is preinstalled on GitHub's macOS images and is the normal local
# setup, but the script must still work without it.
prettify() {
    if command -v xcbeautify >/dev/null 2>&1; then
        xcbeautify
    else
        cat
    fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
_INTERRUPTED=false

print_summary() {
    $LIST_MODE && return
    local total_count=${#JOB_NAMES[@]}
    [ "$total_count" -eq 0 ] && return

    echo
    printf '%s' "$BOLD"; printf '═%.0s' $(seq 1 74); printf '%s\n' "$RESET"
    if $_INTERRUPTED; then
        printf "%s  SUMMARY  %s(interrupted)%s\n" "$BOLD" "$YELLOW" "$RESET"
    else
        printf "%s  SUMMARY%s\n" "$BOLD" "$RESET"
    fi
    printf '%s' "$BOLD"; printf '═%.0s' $(seq 1 74); printf '%s\n' "$RESET"
    echo
    printf "  %s%s%s\n\n" "$DIM" "$OUTPUT_DIR" "$RESET"

    local pass_count=0 i
    for i in "${!JOB_NAMES[@]}"; do
        local name status icon dur_str detail
        name="${JOB_NAMES[$i]}"
        status="${JOB_STATUSES[$i]}"
        dur_str=$(format_duration "${JOB_DURATIONS[$i]}")

        if [ "$status" -eq 0 ]; then
            icon="${GREEN}✅${RESET}"; pass_count=$((pass_count + 1))
        else
            icon="${RED}❌${RESET}"
        fi

        if [ "${JOB_ACTIONS[$i]}" = "test" ]; then
            printf -v detail "%-34s  %s" "$name" "${JOB_TEST_SUMMARIES[$i]}"
        else
            printf -v detail "%s" "$name"
        fi
        printf "  %b  %-56s %s(%s)%s\n" "$icon" "$detail" "$DIM" "$dur_str" "$RESET"

        if [ "$status" -ne 0 ]; then
            printf "      %sLog:      %s%s\n" "$DIM" "${JOB_LOG_PATHS[$i]}" "$RESET"
            [ -n "${JOB_XCRESULT_PATHS[$i]}" ] && \
                printf "      %sxcresult: %s%s\n" "$DIM" "${JOB_XCRESULT_PATHS[$i]}" "$RESET"
        fi
    done

    echo
    printf '─%.0s' $(seq 1 74); echo

    local total_dur=0 d
    for d in "${JOB_DURATIONS[@]}"; do total_dur=$((total_dur + d)); done

    local failed=$(( total_count - pass_count ))
    if $_INTERRUPTED; then
        printf "%s%s  %d/%d completed before interrupt ⚠️%s  %s(%s)%s\n" \
            "$YELLOW" "$BOLD" "$pass_count" "$total_count" "$RESET" \
            "$DIM" "$(format_duration $total_dur)" "$RESET"
    elif [ "$failed" -eq 0 ]; then
        printf "%s%s  All %d jobs passed ✅%s  %s(%s)%s\n" \
            "$GREEN" "$BOLD" "$total_count" "$RESET" \
            "$DIM" "$(format_duration $total_dur)" "$RESET"
    else
        printf "%s%s  %d/%d passed — %d failed ❌%s  %s(%s)%s\n" \
            "$RED" "$BOLD" "$pass_count" "$total_count" "$failed" "$RESET" \
            "$DIM" "$(format_duration $total_dur)" "$RESET"
    fi
    printf '═%.0s' $(seq 1 74); printf '%s\n\n' "$RESET"
}

on_interrupt() {
    _INTERRUPTED=true
    printf "\n%s%s  Interrupted — showing partial results...%s\n" "$YELLOW" "$BOLD" "$RESET"
    print_summary
    exit 130
}
trap on_interrupt INT TERM

# ── Job runner ────────────────────────────────────────────────────────────────
record_result() {
    JOB_NAMES+=("$1"); JOB_ACTIONS+=("$2"); JOB_STATUSES+=("$3")
    JOB_LOG_PATHS+=("$4"); JOB_XCRESULT_PATHS+=("$5")
    JOB_TEST_SUMMARIES+=("$6"); JOB_DURATIONS+=("$7")
}

run_job() {
    local id="$1" action="$2" scheme="$3" platform="$4"
    local label

    case "$action" in
        lint) label="SwiftLint" ;;
        spm)  label="swift build --build-tests" ;;
        *)    label="$scheme · $platform" ;;
    esac

    mkdir -p "$OUTPUT_DIR"

    local log_file xcresult_path safe_name
    safe_name=$(sanitize_name "$id")
    log_file="$OUTPUT_DIR/${safe_name}.log"
    xcresult_path=""

    echo
    [ "$_IS_CI" = "true" ] && echo "::group::$id — $label"
    printf "%s%s▸ %-8s %s%s\n" "$BOLD" "$BLUE" "$action" "$label" "$RESET"
    printf "%s  job: %s%s\n" "$DIM" "$id" "$RESET"

    local exit_code=0 start_time end_time
    start_time=$(date +%s)

    case "$action" in
        lint)
            # Not --strict yet: SwiftLint has never gated CI, so the existing
            # warnings need clearing first. Tighten once they are.
            if command -v swiftlint >/dev/null 2>&1; then
                (cd "$PROJECT_ROOT" && swiftlint lint) 2>&1 | tee "$log_file" || exit_code=$?
            else
                echo "swiftlint not installed — skipping (brew install swiftlint)" | tee "$log_file"
            fi
            ;;
        spm)
            (cd "$PROJECT_ROOT" && swift build --build-tests) 2>&1 \
                | tee "$log_file" | prettify || exit_code=$?
            ;;
        build)
            local dest; dest=$(destination_for build "$platform")
            printf "%s  destination: %s%s\n" "$DIM" "$dest" "$RESET"
            xcresult_path="$OUTPUT_DIR/${safe_name}.xcresult"
            rm -rf "$xcresult_path"
            xcodebuild build \
                -project "$PROJECT" \
                -scheme "$scheme" \
                -destination "$dest" \
                -resultBundlePath "$xcresult_path" \
                2>&1 | tee "$log_file" | prettify || exit_code=$?
            ;;
        test)
            local dest; dest=$(destination_for test "$platform")
            printf "%s  destination: %s%s\n" "$DIM" "$dest" "$RESET"
            xcresult_path="$OUTPUT_DIR/${safe_name}.xcresult"
            rm -rf "$xcresult_path"
            xcodebuild test \
                -project "$PROJECT" \
                -scheme "$scheme" \
                -destination "$dest" \
                -resultBundlePath "$xcresult_path" \
                -parallel-testing-enabled NO \
                -test-timeouts-enabled YES \
                -default-test-execution-time-allowance 120 \
                -retry-tests-on-failure \
                2>&1 | tee "$log_file" | prettify || exit_code=$?
            ;;
    esac

    end_time=$(date +%s)
    [ "$_IS_CI" = "true" ] && echo "::endgroup::"

    local test_summary=""
    [ "$action" = "test" ] && test_summary=$(parse_test_results "$log_file" "$exit_code")

    record_result "$label" "$action" "$exit_code" "$log_file" \
        "$xcresult_path" "$test_summary" "$(( end_time - start_time ))"
}

# ── List mode ─────────────────────────────────────────────────────────────────
if $LIST_MODE; then
    echo
    printf "%sGroups%s (make ci-group-<name>, one GitHub job each)\n\n" "$BOLD" "$RESET"
    for g in "${CI_GROUPS[@]}"; do printf "  %s\n" "$g"; done
    echo
    printf "%sJobs%s (make ci-<id>)\n" "$BOLD" "$RESET"
    last_group=""
    for entry in "${JOBS[@]}"; do
        IFS='|' read -r id group action scheme platform <<< "$entry"
        if [ "$group" != "$last_group" ]; then
            printf "\n  %s%s%s\n" "$DIM" "$group" "$RESET"
            last_group="$group"
        fi
        printf "    %-32s %s %s\n" "$id" "$action" "$scheme · $platform"
    done
    echo
    exit 0
fi

# ── Header ────────────────────────────────────────────────────────────────────
if [ -z "$JOB_FILTER" ] || [ -n "$GROUP_FILTER" ]; then
    echo
    printf "%s╔════════════════════════════════════════════════════════════════════════╗%s\n" "$BOLD" "$RESET"
    printf "%s║                        Nuke CI — Build & Test                          ║%s\n" "$BOLD" "$RESET"
    printf "%s╚════════════════════════════════════════════════════════════════════════╝%s\n" "$BOLD" "$RESET"
    echo
    [ -n "$GROUP_FILTER" ] && printf "  %sGroup:  %s%s\n" "$DIM" "$GROUP_FILTER" "$RESET"
    printf "  %sOutput: %s%s\n" "$DIM" "$OUTPUT_DIR" "$RESET"
    echo
    xcodebuild -version 2>/dev/null || true
fi

# ── Dispatch ──────────────────────────────────────────────────────────────────
matched=0
for entry in "${JOBS[@]}"; do
    IFS='|' read -r id group action scheme platform <<< "$entry"

    if [ -n "$JOB_FILTER" ] && [ "$id" != "$JOB_FILTER" ]; then continue; fi
    if [ -n "$GROUP_FILTER" ] && [ "$group" != "$GROUP_FILTER" ]; then continue; fi

    matched=$((matched + 1))
    run_job "$id" "$action" "$scheme" "$platform"
done

if [ "$matched" -eq 0 ]; then
    if [ -n "$GROUP_FILTER" ]; then
        printf "%sNo group '%s'. Run 'make ci-list' to see all groups.%s\n" "$YELLOW" "$GROUP_FILTER" "$RESET" >&2
    else
        printf "%sNo job '%s'. Run 'make ci-list' to see all job IDs.%s\n" "$YELLOW" "$JOB_FILTER" "$RESET" >&2
    fi
    exit 1
fi

print_summary

failed=0
for status in "${JOB_STATUSES[@]}"; do
    [ "$status" -ne 0 ] && failed=$((failed + 1))
done
[ "$failed" -gt 0 ] && exit 1
exit 0
