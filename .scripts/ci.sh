#!/bin/bash
set -o pipefail

# Usage: ci.sh [--list | <selector>]
#   (no args)     Run every job
#   --list        Print every job, with the group and action it can be selected by
#   <selector>    Run every job matching a job id, a group, or an action
#
# This script is the single source of truth for the CI matrix. The GitHub
# workflow does nothing except pass it a group name, so `make ci` runs exactly
# what CI runs. This is what stops the drift that left `validate.sh` unused for
# four years.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT="$PROJECT_ROOT/Nuke.xcodeproj"

# Logs go to a timestamped temp directory, not the console and not the repo.
# CI overrides this so the workflow can upload xcresult bundles from a fixed path.
if [ -n "$NUKE_CI_OUTPUT_DIR" ]; then
    OUTPUT_DIR="$NUKE_CI_OUTPUT_DIR"
else
    OUTPUT_ROOT="${TMPDIR:-/tmp}"
    OUTPUT_ROOT="${OUTPUT_ROOT%/}/nuke-ci"
    OUTPUT_DIR="$OUTPUT_ROOT/$(date +%Y%m%d-%H%M%S)"
fi

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

# ── Arguments ─────────────────────────────────────────────────────────────────
LIST_MODE=false
SELECTOR=""
case "${1:-}" in
    --list) LIST_MODE=true ;;
    "")     ;;
    -*)     echo "error: unknown option '$1'" >&2; exit 2 ;;
    *)      SELECTOR="$1" ;;
esac

# ── Colors ────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; BLUE=$'\033[0;34m'
    YELLOW=$'\033[0;33m'; CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    RED=''; GREEN=''; BLUE=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

# GitHub Actions renders collapsible groups from ::group:: markers.
_IS_CI="${GITHUB_ACTIONS:-false}"

# ── Helpers ───────────────────────────────────────────────────────────────────
format_duration() {
    if [ "$1" -ge 60 ]; then
        printf "%dm %ds" $(( $1 / 60 )) $(( $1 % 60 ))
    else
        printf "%ds" "$1"
    fi
}

# Swift Testing prints one authoritative tally per attempt:
#   "Test run with 940 tests in 74 suites passed after 1.463 seconds."
# Take the first, which is the full suite: -retry-tests-on-failure re-runs only
# the tests that failed, so a later tally counts a subset. Note that this greps
# the raw log — xcbeautify drops the tally from the prettified stream.
parse_test_results() {
    local log="$1" status="$2" total failed
    total=$(grep -oE "Test run with [0-9]+ test" "$log" 2>/dev/null | head -1 | grep -oE "[0-9]+")
    [ -z "$total" ] && { echo "—"; return; }

    # Failure lines span every attempt, which is what we want: if the job still
    # passed, each one was rescued by a retry, i.e. a flaky test.
    failed=$(grep -cE "Test .*\(.*\) failed after" "$log" 2>/dev/null | tr -d ' ')
    failed=${failed:-0}

    if [ "$failed" -gt 0 ] && [ "$status" -eq 0 ]; then
        # xcodebuild exited 0 despite failures, so -retry-tests-on-failure
        # rescued them. Surface it — a silent retry is a hidden flaky test.
        echo "$total run · $(( total - failed )) ✓ · $failed flaky ⚠️"
    elif [ "$failed" -gt 0 ]; then
        echo "$total run · $(( total - failed )) ✓ · $failed ✗"
    elif [ "$status" -eq 0 ]; then
        echo "$total run · $total ✓"
    else
        # No test reported a failure, yet xcodebuild failed: a hung test killed
        # by its time limit, a crashed runner, or a build error. Don't claim a
        # clean tally — the log is the only place to find out which.
        echo "$total run · run did not complete ✗"
    fi
}

# Pick the newest available simulator matching a name pattern, boot it, and set
# SIM_SELECTOR and SIM_NAME. Resolving at runtime is what keeps this working
# across runner-image updates — pinning "OS=26.4.1" is what forced the repeated
# ci.yml churn in the past. The selector is a UDID rather than a name because a
# machine with several installed runtimes has several devices sharing a name, and
# xcodebuild is then free to pick a different one than the one booted here.
# Booting up front rather than letting xcodebuild do it lazily avoids the
# first-test-run flakiness that commit a439c17a worked around.
resolve_simulator() {
    local line udid
    line=$(xcrun simctl list devices available 2>/dev/null | grep -E "^[[:space:]]+${1}" | tail -1)
    udid=$(printf '%s' "$line" | grep -oE '[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}' | head -1)
    if [ -z "$udid" ]; then
        # Nothing matched. Fall back to the name so that xcodebuild reports what
        # is missing, rather than failing on an empty destination.
        SIM_SELECTOR="name=$2"; SIM_NAME="$2"
        return
    fi
    SIM_SELECTOR="id=$udid"
    SIM_NAME=$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | sed "s/ ($udid).*//")
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
}

# Sets DEST, plus DEST_NAME for the simulator platforms. Tests need a concrete
# simulator; compile-only jobs use a generic destination so they never pay the
# simulator boot cost. Caching in globals rather than echoing is what keeps it to
# one boot per platform: a command substitution would resolve and re-boot in a
# subshell for every job.
_IOS_DEST=""; _IOS_NAME=""
_TV_DEST="";  _TV_NAME=""
set_destination() {
    DEST_NAME=""
    if [ "$1" = "build" ]; then
        DEST="generic/platform=$2"
        return
    fi
    case "$2" in
        iOS)
            if [ -z "$_IOS_DEST" ]; then
                resolve_simulator "iPhone [0-9]" "iPhone 17 Pro"
                _IOS_DEST="platform=iOS Simulator,$SIM_SELECTOR"; _IOS_NAME="$SIM_NAME"
            fi
            DEST="$_IOS_DEST"; DEST_NAME="$_IOS_NAME" ;;
        tvOS)
            if [ -z "$_TV_DEST" ]; then
                resolve_simulator "Apple TV" "Apple TV"
                _TV_DEST="platform=tvOS Simulator,$SIM_SELECTOR"; _TV_NAME="$SIM_NAME"
            fi
            DEST="$_TV_DEST"; DEST_NAME="$_TV_NAME" ;;
        macOS) DEST="platform=macOS" ;;
        *)     DEST="generic/platform=$2" ;;
    esac
}

# xcbeautify is preinstalled on GitHub's macOS images and is the normal local
# setup, but the script must still work without it.
prettify() {
    if command -v xcbeautify >/dev/null 2>&1; then xcbeautify; else cat; fi
}

# ── Progress line ─────────────────────────────────────────────────────────────
#
# An interactive run hides the build output and repaints one line in place:
#
#     ⠹  9/22  40%  4m 21s  ·  Nuke · iOS  test
#
# Finished jobs are printed above it, so the scrollback reads as the final
# summary being built up. CI keeps the full output stream, and NUKE_CI_VERBOSE=1
# forces it locally too.

PROGRESS=false
if [ -t 1 ] && [ "$_IS_CI" != "true" ] && [ -z "$NUKE_CI_VERBOSE" ] && ! $LIST_MODE; then
    PROGRESS=true
fi

_SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
CI_START=$SECONDS
JOBS_TOTAL=0
JOBS_DONE=0
CURRENT_JOB=""

# Nothing in here may fork: it runs once per line of build output.
paint() {
    local elapsed=$(( SECONDS - CI_START )) dur pct=0
    if [ "$elapsed" -ge 60 ]; then
        printf -v dur "%dm %02ds" $(( elapsed / 60 )) $(( elapsed % 60 ))
    else
        printf -v dur "%ds" "$elapsed"
    fi
    [ "$JOBS_TOTAL" -gt 0 ] && pct=$(( JOBS_DONE * 100 / JOBS_TOTAL ))
    printf '\r\033[2K  %s  %s%d/%d%s  %s%d%%  %s%s  %s' \
        "${CYAN}${_SPINNER[$(( $1 % 10 ))]}${RESET}" \
        "$BOLD" "$JOBS_DONE" "$JOBS_TOTAL" "$RESET" \
        "$DIM" "$pct" "$dur" "$RESET" "$CURRENT_JOB"
}

erase_progress() {
    $PROGRESS && printf '\r\033[2K'
}

# Terminal stage of a job's pipeline when the progress line is showing: swallow
# the build output and tick the spinner on every line.
#
# The read is blocking on purpose. `read -t 1` would let the clock tick during a
# silent compile, but bash 3.2 — which is what /bin/bash is on macOS — returns 1
# on timeout, indistinguishable from EOF, so the sink exited at the first quiet
# second and killed the build with SIGPIPE.
progress_sink() {
    local line spin=0
    paint 0
    while IFS= read -r line; do
        spin=$(( spin + 1 ))
        paint "$spin"
    done
    return 0
}

# ── Results ───────────────────────────────────────────────────────────────────
JOB_IDS=()
JOB_LABELS=()
JOB_STATUSES=()
JOB_SUMMARIES=()
JOB_DURATIONS=()

# One row of the running tally, in the same shape as the final summary.
# A negative status means the job could not run at all — see the lint case.
print_result_row() {
    local label="$1" status="$2" summary="$3" duration="$4" icon detail
    if [ "$status" -lt 0 ]; then   icon="${YELLOW}⏭️${RESET} "
    elif [ "$status" -eq 0 ]; then icon="${GREEN}✅${RESET}"
    else                           icon="${RED}❌${RESET}"; fi
    printf -v detail "%-34s  %s" "$label" "$summary"
    printf "  %b  %-56s %s(%s)%s\n" "$icon" "$detail" "$DIM" "$(format_duration "$duration")" "$RESET"
}

_INTERRUPTED=false

print_summary() {
    local total=${#JOB_IDS[@]} i
    [ "$total" -eq 0 ] && return

    local passed=0 failed=0 skipped=0
    for i in "${!JOB_IDS[@]}"; do
        if [ "${JOB_STATUSES[$i]}" -lt 0 ]; then   skipped=$(( skipped + 1 ))
        elif [ "${JOB_STATUSES[$i]}" -eq 0 ]; then passed=$(( passed + 1 ))
        else                                       failed=$(( failed + 1 )); fi
    done

    # With the progress line, every job already printed its row as it finished.
    if ! $PROGRESS; then
        echo
        for i in "${!JOB_IDS[@]}"; do
            print_result_row "${JOB_LABELS[$i]}" "${JOB_STATUSES[$i]}" \
                "${JOB_SUMMARIES[$i]}" "${JOB_DURATIONS[$i]}"
        done
    fi

    # Failures are worth repeating, with the logs needed to debug them.
    local printed_header=false xcresult
    for i in "${!JOB_IDS[@]}"; do
        [ "${JOB_STATUSES[$i]}" -le 0 ] && continue
        $printed_header || { echo; printed_header=true; }
        printf "  %s%s%s\n" "$RED$BOLD" "${JOB_LABELS[$i]}" "$RESET"
        printf "      %slog:      %s%s\n" "$DIM" "$OUTPUT_DIR/${JOB_IDS[$i]}.txt" "$RESET"
        xcresult="$OUTPUT_DIR/${JOB_IDS[$i]}.xcresult"
        [ -d "$xcresult" ] && printf "      %sxcresult: %s%s\n" "$DIM" "$xcresult" "$RESET"
    done

    local ran=$(( passed + failed )) plural="s"
    [ "$passed" -eq 1 ] && plural=""
    echo
    if $_INTERRUPTED; then
        printf "  %s%s%d/%d completed before interrupt ⚠️%s" "$YELLOW" "$BOLD" "$total" "$JOBS_TOTAL" "$RESET"
    elif [ "$failed" -gt 0 ]; then
        printf "  %s%s%d/%d passed — %d failed ❌%s" "$RED" "$BOLD" "$passed" "$ran" "$failed" "$RESET"
    elif [ "$passed" -gt 0 ]; then
        printf "  %s%sAll %d job%s passed ✅%s" "$GREEN" "$BOLD" "$passed" "$plural" "$RESET"
    else
        printf "  %s%sNothing ran ⚠️%s" "$YELLOW" "$BOLD" "$RESET"
    fi
    [ "$skipped" -gt 0 ] && printf "  %s· %d skipped%s" "$DIM" "$skipped" "$RESET"
    printf "  %s(%s)%s\n" "$DIM" "$(format_duration $(( SECONDS - CI_START )))" "$RESET"
    printf "  %slogs: %s%s\n\n" "$DIM" "$OUTPUT_DIR" "$RESET"
}

on_interrupt() {
    _INTERRUPTED=true
    erase_progress
    printf "\n%s%s  Interrupted — showing partial results...%s\n" "$YELLOW" "$BOLD" "$RESET"
    print_summary
    exit 130
}
trap on_interrupt INT TERM

# ── Job runner ────────────────────────────────────────────────────────────────

# Runs a command with its output teed to the raw log (which parse_test_results
# greps), prettified into a readable log, and then either swallowed by the
# progress line or streamed as-is.
run_streamed() {
    local id="$1"; shift
    local rc=0
    if $PROGRESS; then
        "$@" 2>&1 | tee "$OUTPUT_DIR/$id.log" | prettify | tee "$OUTPUT_DIR/$id.txt" | progress_sink || rc=$?
    else
        "$@" 2>&1 | tee "$OUTPUT_DIR/$id.log" | prettify | tee "$OUTPUT_DIR/$id.txt" || rc=$?
    fi
    return $rc
}

run_job() {
    local id="$1" action="$2" scheme="$3" platform="$4"

    local label
    case "$action" in
        lint) label="SwiftLint" ;;
        spm)  label="swift build --build-tests" ;;
        *)    label="$scheme · $platform" ;;
    esac

    DEST=""; DEST_NAME=""
    case "$action" in
        build|test) set_destination "$action" "$platform" ;;
    esac

    if $PROGRESS; then
        CURRENT_JOB="${BOLD}${label}${RESET}${DIM}  ${action}${RESET}"
    else
        echo
        [ "$_IS_CI" = "true" ] && echo "::group::$id — $label"
        printf "%s%s▸ %-8s %s%s\n" "$BOLD" "$BLUE" "$action" "$label" "$RESET"
        printf "%s  job: %s%s\n" "$DIM" "$id" "$RESET"
        # The destination carries a UDID, so name the device it resolved to.
        [ -n "$DEST" ] && printf "%s  destination: %s%s%s\n" \
            "$DIM" "$DEST" "${DEST_NAME:+  ($DEST_NAME)}" "$RESET"
    fi

    local exit_code=0 summary="" start=$SECONDS
    rm -rf "$OUTPUT_DIR/$id.xcresult"

    case "$action" in
        lint)
            # Not --strict yet: SwiftLint has never gated CI, so the existing
            # warnings need clearing first. Tighten once they are.
            if command -v swiftlint >/dev/null 2>&1; then
                run_streamed "$id" env -C "$PROJECT_ROOT" swiftlint lint || exit_code=$?
            else
                # A negative status marks the job skipped rather than passed —
                # reporting green for a job that never ran is how CI goes stale.
                exit_code=-1
                summary="not installed — brew install swiftlint"
            fi
            ;;
        spm)
            run_streamed "$id" env -C "$PROJECT_ROOT" swift build --build-tests || exit_code=$?
            ;;
        build)
            run_streamed "$id" \
                xcodebuild build \
                    -project "$PROJECT" \
                    -scheme "$scheme" \
                    -destination "$DEST" \
                    -resultBundlePath "$OUTPUT_DIR/$id.xcresult" || exit_code=$?
            ;;
        test)
            # The suites carry their own `.timeLimit` trait, so a hung test is
            # caught by Swift Testing rather than by an xcodebuild allowance.
            run_streamed "$id" \
                xcodebuild test \
                    -project "$PROJECT" \
                    -scheme "$scheme" \
                    -destination "$DEST" \
                    -resultBundlePath "$OUTPUT_DIR/$id.xcresult" \
                    -parallel-testing-enabled NO \
                    -retry-tests-on-failure || exit_code=$?
            ;;
    esac

    [ "$_IS_CI" = "true" ] && echo "::endgroup::"

    local duration=$(( SECONDS - start ))
    [ "$action" = "test" ] && summary=$(parse_test_results "$OUTPUT_DIR/$id.log" "$exit_code")

    JOB_IDS+=("$id"); JOB_LABELS+=("$label"); JOB_STATUSES+=("$exit_code")
    JOB_SUMMARIES+=("$summary"); JOB_DURATIONS+=("$duration")
    JOBS_DONE=$(( JOBS_DONE + 1 ))

    if $PROGRESS; then
        erase_progress
        print_result_row "$label" "$exit_code" "$summary" "$duration"
    fi
}

# ── List mode ─────────────────────────────────────────────────────────────────
if $LIST_MODE; then
    printf "\n%sJobs%s  %sgrouped by CI group — pass any id, group, or action to make ci-<name>%s\n" \
        "$BOLD" "$RESET" "$DIM" "$RESET"
    last_group=""
    for entry in "${JOBS[@]}"; do
        IFS='|' read -r id group action scheme platform <<< "$entry"
        if [ "$group" != "$last_group" ]; then
            printf "\n  %s%s%s\n" "$DIM" "$group" "$RESET"
            last_group="$group"
        fi
        printf "    %-32s %-6s %s\n" "$id" "$action" "$scheme · $platform"
    done
    echo
    exit 0
fi

# ── Job selection ─────────────────────────────────────────────────────────────
# Resolved up front so the progress line knows the denominator.
SELECTED=()
for entry in "${JOBS[@]}"; do
    IFS='|' read -r id group action scheme platform <<< "$entry"
    if [ -z "$SELECTOR" ] || [ "$SELECTOR" = "$id" ] || [ "$SELECTOR" = "$group" ] || [ "$SELECTOR" = "$action" ]; then
        SELECTED+=("$entry")
    fi
done

if [ "${#SELECTED[@]}" -eq 0 ]; then
    printf "%sNothing matches '%s'. Run 'make ci-list' to see every job, group, and action.%s\n" \
        "$YELLOW" "$SELECTOR" "$RESET" >&2
    exit 1
fi
JOBS_TOTAL=${#SELECTED[@]}

# ── Run ───────────────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
[ -n "$OUTPUT_ROOT" ] && ln -sfn "$OUTPUT_DIR" "$OUTPUT_ROOT/latest"

echo
printf "  %sNuke CI%s  %s%d job" "$BOLD" "$RESET" "$DIM" "$JOBS_TOTAL"
[ "$JOBS_TOTAL" -eq 1 ] || printf "s"
[ -n "$SELECTOR" ] && printf " · %s" "$SELECTOR"
printf "%s\n" "$RESET"
printf "  %slogs: %s%s\n" "$DIM" "$OUTPUT_DIR" "$RESET"
echo

for entry in "${SELECTED[@]}"; do
    IFS='|' read -r id group action scheme platform <<< "$entry"
    run_job "$id" "$action" "$scheme" "$platform"
done

print_summary

for status in "${JOB_STATUSES[@]}"; do
    [ "$status" -gt 0 ] && exit 1
done
exit 0
