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
    YELLOW=$'\033[0;33m'; CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    RED=''; GREEN=''; BLUE=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

# GitHub Actions renders collapsible groups from ::group:: markers.
_IS_CI="${GITHUB_ACTIONS:-false}"

# The live dashboard replaces the raw output stream on an interactive terminal.
# CI keeps the full stream, and NUKE_CI_VERBOSE=1 forces it locally too.
DASH_TAIL="${NUKE_CI_TAIL:-8}"
DASH_HEIGHT=$(( DASH_TAIL + 4 ))
DASH_ACTIVE=false
if [ -t 1 ] && [ "$_IS_CI" != "true" ] && [ -z "$NUKE_CI_VERBOSE" ] && ! $LIST_MODE; then
    DASH_ACTIVE=true
fi

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
# setup, but the script must still work without it. Colour is disabled under the
# dashboard so the tail window can be truncated to width without cutting an
# escape sequence in half.
prettify() {
    if command -v xcbeautify >/dev/null 2>&1; then
        if $DASH_ACTIVE; then xcbeautify --disable-colored-output; else xcbeautify; fi
    else
        cat
    fi
}

# ── Live dashboard ────────────────────────────────────────────────────────────
#
# A fixed-height block pinned below the scrolling result lines:
#
#     ⠹  ███████░░░░░░░░░  9/22  40%  4m 21s
#     ▸ Nuke · iOS  test  ·  platform=iOS Simulator,name=iPhone 17 Pro
#
#     │ <last DASH_TAIL lines of output>
#
# The block is exactly DASH_HEIGHT lines, so repainting is "cursor up
# DASH_HEIGHT, rewrite every line". dash_close erases it and leaves the cursor
# at its top, which is how completed jobs get printed above it.
#
# Nothing in the paint path may fork: it runs once per line of build output.

_DASH_OPEN=false
_TERM_COLS=80
JOBS_TOTAL=0
JOBS_DONE=0
CURRENT_JOB=""
CI_START_SECONDS=$SECONDS
RING=()

_SPINNER=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# stty rather than tput, because tput reports stale values inside the pipeline
# subshell where the painting happens.
refresh_term_cols() {
    local size
    size=$(stty size </dev/tty 2>/dev/null) || size="24 80"
    _TERM_COLS="${size##* }"
    case "$_TERM_COLS" in
        ''|*[!0-9]*) _TERM_COLS=80 ;;
    esac
    # A pty with no real geometry reports 0; don't let that collapse the window.
    [ "$_TERM_COLS" -lt 40 ] && _TERM_COLS=80
}

dash_open() {
    $DASH_ACTIVE || return 0
    $_DASH_OPEN && return 0
    local i
    for ((i = 0; i < DASH_HEIGHT; i++)); do printf '\n'; done
    _DASH_OPEN=true
}

dash_close() {
    $DASH_ACTIVE || return 0
    $_DASH_OPEN || return 0
    local buf i
    buf=$'\033['"$DASH_HEIGHT"'A'
    for ((i = 0; i < DASH_HEIGHT; i++)); do buf+=$'\033[2K\n'; done
    buf+=$'\033['"$DASH_HEIGHT"'A'
    printf '%s' "$buf"
    _DASH_OPEN=false
}

ring_push() {
    RING+=("${1%$'\r'}")
    if [ "${#RING[@]}" -gt "$DASH_TAIL" ]; then
        RING=("${RING[@]:1}")
    fi
}

dash_paint() {
    $_DASH_OPEN || return 0

    local spin_idx="$1"
    local width=16 pct=0 filled=0 bar="" i
    if [ "$JOBS_TOTAL" -gt 0 ]; then
        pct=$(( JOBS_DONE * 100 / JOBS_TOTAL ))
        filled=$(( JOBS_DONE * width / JOBS_TOTAL ))
    fi
    for ((i = 0; i < width; i++)); do
        if ((i < filled)); then bar+="█"; else bar+="░"; fi
    done

    # Inlined rather than calling format_duration: a command substitution here
    # would fork once per line of build output.
    local elapsed=$(( SECONDS - CI_START_SECONDS )) dur
    if [ "$elapsed" -ge 60 ]; then
        printf -v dur "%dm %02ds" $(( elapsed / 60 )) $(( elapsed % 60 ))
    else
        printf -v dur "%ds" "$elapsed"
    fi

    local inner=$(( _TERM_COLS - 6 ))
    [ "$inner" -lt 20 ] && inner=20

    local buf=$'\033['"$DASH_HEIGHT"'A'
    buf+=$'\033[2K\n'
    buf+=$'\033[2K'"  ${CYAN}${_SPINNER[$((spin_idx % 10))]}${RESET}  ${bar}  ${BOLD}${JOBS_DONE}/${JOBS_TOTAL}${RESET}  ${pct}%  ${DIM}${dur}${RESET}"$'\n'
    buf+=$'\033[2K'"  ${BLUE}${BOLD}▸${RESET} ${CURRENT_JOB}"$'\n'
    buf+=$'\033[2K\n'

    local n=${#RING[@]} idx line
    for ((i = 0; i < DASH_TAIL; i++)); do
        idx=$(( i - (DASH_TAIL - n) ))
        line=""
        if [ "$idx" -ge 0 ] && [ "$idx" -lt "$n" ]; then
            line="${RING[$idx]}"
            line="${line:0:$inner}"
        fi
        buf+=$'\033[2K'"  ${DIM}│ ${line}${RESET}"$'\n'
    done

    printf '%s' "$buf"
}

# Terminal stage of a job's pipeline: swallow the output, keep the last
# DASH_TAIL lines, and repaint on each one.
#
# The read is blocking on purpose. `read -t 1` would let the clock tick during
# a silent compile, but bash 3.2 — which is what /bin/bash is on macOS —
# returns 1 on timeout, indistinguishable from EOF, so the sink exited at the
# first quiet second and killed the build with SIGPIPE.
dash_sink() {
    local line spin=0
    RING=()
    dash_paint 0
    while IFS= read -r line; do
        ring_push "$line"
        spin=$(( spin + 1 ))
        dash_paint "$spin"
    done
    return 0
}

# ── Summary ───────────────────────────────────────────────────────────────────
_INTERRUPTED=false

print_summary() {
    $LIST_MODE && return
    local total_count=${#JOB_NAMES[@]}
    [ "$total_count" -eq 0 ] && return

    local pass_count=0 i
    for i in "${!JOB_NAMES[@]}"; do
        [ "${JOB_STATUSES[$i]}" -eq 0 ] && pass_count=$((pass_count + 1))
    done

    # Under the dashboard every job already printed its row as it finished, so
    # only the failures are worth repeating — with the logs needed to debug them.
    if ! $DASH_ACTIVE; then
        echo
        for i in "${!JOB_NAMES[@]}"; do
            print_result_row "${JOB_NAMES[$i]}" "${JOB_ACTIONS[$i]}" \
                "${JOB_STATUSES[$i]}" "${JOB_TEST_SUMMARIES[$i]}" "${JOB_DURATIONS[$i]}"
        done
    fi

    local printed_header=false
    for i in "${!JOB_NAMES[@]}"; do
        [ "${JOB_STATUSES[$i]}" -eq 0 ] && continue
        if ! $printed_header; then echo; printed_header=true; fi
        printf "  %s%s%s\n" "$RED$BOLD" "${JOB_NAMES[$i]}" "$RESET"
        printf "      %slog:      %s%s\n" "$DIM" "${JOB_LOG_PATHS[$i]%.log}.txt" "$RESET"
        [ -n "${JOB_XCRESULT_PATHS[$i]}" ] && \
            printf "      %sxcresult: %s%s\n" "$DIM" "${JOB_XCRESULT_PATHS[$i]}" "$RESET"
    done

    local total_dur=0 d
    for d in "${JOB_DURATIONS[@]}"; do total_dur=$((total_dur + d)); done

    echo
    local failed=$(( total_count - pass_count ))
    if $_INTERRUPTED; then
        printf "  %s%s%d/%d completed before interrupt ⚠️%s  %s(%s)%s\n" \
            "$YELLOW" "$BOLD" "$pass_count" "$total_count" "$RESET" \
            "$DIM" "$(format_duration $total_dur)" "$RESET"
    elif [ "$failed" -eq 0 ]; then
        printf "  %s%sAll %d jobs passed ✅%s  %s(%s)%s\n" \
            "$GREEN" "$BOLD" "$total_count" "$RESET" \
            "$DIM" "$(format_duration $total_dur)" "$RESET"
    else
        printf "  %s%s%d/%d passed — %d failed ❌%s  %s(%s)%s\n" \
            "$RED" "$BOLD" "$pass_count" "$total_count" "$failed" "$RESET" \
            "$DIM" "$(format_duration $total_dur)" "$RESET"
    fi
    printf "  %slogs: %s%s\n\n" "$DIM" "$OUTPUT_DIR" "$RESET"
}

on_interrupt() {
    _INTERRUPTED=true
    dash_close
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

# One row of the running tally, in the same shape as the final summary so the
# scrollback reads as the summary being built up.
print_result_row() {
    local label="$1" action="$2" status="$3" test_summary="$4" duration="$5"
    local icon detail
    if [ "$status" -eq 0 ]; then icon="${GREEN}✅${RESET}"; else icon="${RED}❌${RESET}"; fi
    if [ "$action" = "test" ]; then
        printf -v detail "%-34s  %s" "$label" "$test_summary"
    else
        printf -v detail "%s" "$label"
    fi
    printf "  %b  %-56s %s(%s)%s\n" "$icon" "$detail" "$DIM" "$(format_duration "$duration")" "$RESET"
}

# Runs a command with its output teed to the raw log (which parse_test_results
# greps), prettified into a readable log, and then either shown in the dashboard
# tail window or streamed as-is.
run_streamed() {
    local raw="$1" pretty="$2"; shift 2
    local rc=0
    if $DASH_ACTIVE; then
        "$@" 2>&1 | tee "$raw" | prettify | tee "$pretty" | dash_sink || rc=$?
    else
        "$@" 2>&1 | tee "$raw" | prettify | tee "$pretty" || rc=$?
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

    mkdir -p "$OUTPUT_DIR"

    local log_file pretty_log xcresult_path safe_name
    safe_name=$(sanitize_name "$id")
    log_file="$OUTPUT_DIR/${safe_name}.log"
    pretty_log="$OUTPUT_DIR/${safe_name}.txt"
    xcresult_path=""

    local dest=""
    case "$action" in
        build) dest=$(destination_for build "$platform") ;;
        test)  dest=$(destination_for test "$platform") ;;
    esac

    if $DASH_ACTIVE; then
        CURRENT_JOB="${BOLD}${label}${RESET}${DIM}  ${action}${dest:+  ·  $dest}${RESET}"
        refresh_term_cols
        dash_open
    else
        echo
        [ "$_IS_CI" = "true" ] && echo "::group::$id — $label"
        printf "%s%s▸ %-8s %s%s\n" "$BOLD" "$BLUE" "$action" "$label" "$RESET"
        printf "%s  job: %s%s\n" "$DIM" "$id" "$RESET"
        [ -n "$dest" ] && printf "%s  destination: %s%s\n" "$DIM" "$dest" "$RESET"
    fi

    local exit_code=0 start_time end_time
    start_time=$(date +%s)

    case "$action" in
        lint)
            # Not --strict yet: SwiftLint has never gated CI, so the existing
            # warnings need clearing first. Tighten once they are.
            if command -v swiftlint >/dev/null 2>&1; then
                run_streamed "$log_file" "$pretty_log" \
                    env -C "$PROJECT_ROOT" swiftlint lint || exit_code=$?
            else
                echo "swiftlint not installed — skipping (brew install swiftlint)" > "$log_file"
            fi
            ;;
        spm)
            run_streamed "$log_file" "$pretty_log" \
                env -C "$PROJECT_ROOT" swift build --build-tests || exit_code=$?
            ;;
        build)
            xcresult_path="$OUTPUT_DIR/${safe_name}.xcresult"
            rm -rf "$xcresult_path"
            run_streamed "$log_file" "$pretty_log" \
                xcodebuild build \
                    -project "$PROJECT" \
                    -scheme "$scheme" \
                    -destination "$dest" \
                    -resultBundlePath "$xcresult_path" || exit_code=$?
            ;;
        test)
            xcresult_path="$OUTPUT_DIR/${safe_name}.xcresult"
            rm -rf "$xcresult_path"
            run_streamed "$log_file" "$pretty_log" \
                xcodebuild test \
                    -project "$PROJECT" \
                    -scheme "$scheme" \
                    -destination "$dest" \
                    -resultBundlePath "$xcresult_path" \
                    -parallel-testing-enabled NO \
                    -test-timeouts-enabled YES \
                    -default-test-execution-time-allowance 120 \
                    -retry-tests-on-failure || exit_code=$?
            ;;
    esac

    end_time=$(date +%s)
    if [ "$_IS_CI" = "true" ]; then echo "::endgroup::"; fi

    local test_summary="" duration=$(( end_time - start_time ))
    [ "$action" = "test" ] && test_summary=$(parse_test_results "$log_file" "$exit_code")

    record_result "$label" "$action" "$exit_code" "$log_file" \
        "$xcresult_path" "$test_summary" "$duration"

    JOBS_DONE=$(( JOBS_DONE + 1 ))
    if $DASH_ACTIVE; then
        dash_close
        print_result_row "$label" "$action" "$exit_code" "$test_summary" "$duration"
    fi
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

# ── Job selection ─────────────────────────────────────────────────────────────
# Resolved up front so the progress bar knows the denominator.
SELECTED=()
for entry in "${JOBS[@]}"; do
    IFS='|' read -r id group action scheme platform <<< "$entry"
    if [ -n "$JOB_FILTER" ] && [ "$id" != "$JOB_FILTER" ]; then continue; fi
    if [ -n "$GROUP_FILTER" ] && [ "$group" != "$GROUP_FILTER" ]; then continue; fi
    SELECTED+=("$entry")
done
JOBS_TOTAL=${#SELECTED[@]}

# ── Header ────────────────────────────────────────────────────────────────────
if [ "$JOBS_TOTAL" -gt 0 ]; then
    echo
    printf "  %sNuke CI%s  %s%d job" "$BOLD" "$RESET" "$DIM" "$JOBS_TOTAL"
    [ "$JOBS_TOTAL" -eq 1 ] || printf "s"
    [ -n "$GROUP_FILTER" ] && printf " · group %s" "$GROUP_FILTER"
    printf "%s\n" "$RESET"
    printf "  %slogs: %s%s\n" "$DIM" "$OUTPUT_DIR" "$RESET"
    echo
    mkdir -p "$OUTPUT_DIR"
    [ -n "$OUTPUT_ROOT" ] && ln -sfn "$OUTPUT_DIR" "$OUTPUT_ROOT/latest"
fi

# ── Dispatch ──────────────────────────────────────────────────────────────────
if [ "$JOBS_TOTAL" -eq 0 ]; then
    if [ -n "$GROUP_FILTER" ]; then
        printf "%sNo group '%s'. Run 'make ci-list' to see all groups.%s\n" "$YELLOW" "$GROUP_FILTER" "$RESET" >&2
    else
        printf "%sNo job '%s'. Run 'make ci-list' to see all job IDs.%s\n" "$YELLOW" "$JOB_FILTER" "$RESET" >&2
    fi
    exit 1
fi

for entry in "${SELECTED[@]}"; do
    IFS='|' read -r id group action scheme platform <<< "$entry"
    run_job "$id" "$action" "$scheme" "$platform"
done

print_summary

failed=0
for status in "${JOB_STATUSES[@]}"; do
    [ "$status" -ne 0 ] && failed=$((failed + 1))
done
[ "$failed" -gt 0 ] && exit 1
exit 0
