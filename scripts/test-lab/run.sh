#!/bin/bash
set +x
set -Eeuo pipefail

if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
    printf '%s\n' \
        'Do not export OPENROUTER_API_KEY. The lab requests it securely after build and setup.' >&2
    exit 2
fi

# Replace the runner with an allowlisted process environment before starting
# any external process. On macOS an exec replaces the kernel-visible process
# environment, which provides the isolation that the Android/Linux lab obtains
# by validating /proc/<pid>/environ.
environment_requires_reexec=0
if [[ "${_NILE_IOS_LAB_CLEAN_ENV:-0}" != "1" ]]; then
    environment_requires_reexec=1
fi
while IFS= read -r environment_name; do
    case "$environment_name" in
        _NILE_IOS_LAB_CLEAN_ENV|HOME|PATH|USER|LOGNAME|SHELL|TERM|LANG|\
        LC_ALL|LC_CTYPE|TZ|TMPDIR|DEVELOPER_DIR|CI|PWD|OLDPWD|SHLVL|_) ;;
        NILE_LAB_RESULT_DIR|NILE_LAB_KEEP|NILE_LAB_SIMULATOR_NAME|\
        NILE_LAB_RUNTIME_VERSION|NILE_LAB_MODEL|NILE_LAB_MODEL_SWITCH_TARGET|\
        NILE_LAB_ALLOW_EXPENSIVE_MODEL|NILE_LAB_OPENROUTER_KEY_FILE|\
        NILE_LAB_CAPTURE_VIDEO) ;;
        *) environment_requires_reexec=1 ;;
    esac
done < <(compgen -e)

if (( environment_requires_reexec )); then
    clean_environment=("_NILE_IOS_LAB_CLEAN_ENV=1")
    for environment_name in \
        HOME PATH USER LOGNAME SHELL TERM LANG LC_ALL LC_CTYPE TZ TMPDIR \
        DEVELOPER_DIR CI \
        NILE_LAB_RESULT_DIR NILE_LAB_KEEP NILE_LAB_SIMULATOR_NAME \
        NILE_LAB_RUNTIME_VERSION NILE_LAB_MODEL \
        NILE_LAB_MODEL_SWITCH_TARGET NILE_LAB_ALLOW_EXPENSIVE_MODEL \
        NILE_LAB_OPENROUTER_KEY_FILE NILE_LAB_CAPTURE_VIDEO; do
        environment_value="${!environment_name-}"
        if [[ -n "$environment_value" ]]; then
            clean_environment+=("$environment_name=$environment_value")
        fi
    done
    exec -c /usr/bin/env "${clean_environment[@]}" /bin/bash "$0" "$@"
fi
unset _NILE_IOS_LAB_CLEAN_ENV environment_requires_reexec environment_name

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MODE="${1:-full}"
PINNED_ANDROID_REF="bd5451da891f2d886b9bc35f8ea67d6920df1d98"
PINNED_ANDROID_TREE="3b954e5844f05276d34aaee34a7d3f69169ef9f5"
PINNED_HERMES_REF="$(tr -d '[:space:]' < "$ROOT_DIR/scripts/test-lab/hermes.ref")"
EXPECTED_HERMES_REF="7441e3395f9db0d8319f43bfe07dfb222777101e"
CANONICAL_SIMULATOR_NAME="${NILE_LAB_SIMULATOR_NAME:-iPhone 17 Pro}"
CANONICAL_RUNTIME_VERSION="${NILE_LAB_RUNTIME_VERSION:-26.5}"
SIMULATOR_DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"
SIMULATOR_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-${CANONICAL_RUNTIME_VERSION//./-}"
OPENROUTER_MODELS_URL="https://openrouter.ai/api/v1/models"
MODEL_ID="${NILE_LAB_MODEL:-nvidia/nemotron-3-super-120b-a12b}"
MODEL_SWITCH_TARGET="${NILE_LAB_MODEL_SWITCH_TARGET:-stepfun/step-3.7-flash}"
ALLOW_EXPENSIVE_MODEL="${NILE_LAB_ALLOW_EXPENSIVE_MODEL:-0}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
RESULT_ROOT="${NILE_LAB_RESULT_DIR:-$ROOT_DIR/build/test-lab-results}"
RESULT_DIR="$RESULT_ROOT/$RUN_ID"
LAB_DIR=""
LAB_HOME=""
HERMES_HOME=""
HERMES_INSTALL_DIR=""
HERMES_WORKSPACE=""
HERMES_BIN=""
HERMES_PYTHON=""
HERMES_PID=""
HERMES_PORT=""
HERMES_TOKEN=""
SIMULATOR_UDID=""
LAB_OPENROUTER_API_KEY=""
CLI_SESSION_ID=""
REFRESH_SEED_PID=""
KEY_HANDOFF_FILE="${NILE_LAB_OPENROUTER_KEY_FILE:-}"
LAB_STATUS="starting"
LANE_FAILURES=0
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
DIAGNOSTIC_MARKER=""
CLI_MARKER="NILE-CLI-FIXTURE-OK"
GOAL_PROGRESS_MARKER="NILE-GOAL-STEP-ONE"
GOAL_DONE_MARKER="NILE-GOAL-DONE"
GOAL_MAX_TURNS=5

usage() {
    cat <<'EOF'
Usage: scripts/test-lab/run.sh [unit|ui|accessibility|visual|smoke|full|drive|installer]

  unit       analyze, test, and unsigned Release-build the current Swift tree
  ui         run deterministic XCUITests in a disposable Simulator
  accessibility
             run large-text, reduced-motion, touch-target, and keyboard checks
  visual     capture onboarding in a disposable Simulator and run strict compare
  smoke      run the production app against fresh pinned, unmodified Hermes
  full       run all gates; block paid smoke if a deterministic gate is red
  drive      leave a disposable Simulator and isolated Hermes up until Ctrl-C
  installer verify a fresh pinned Hermes installation without starting a model

Real-Hermes lanes use OpenRouter and request a key only after the production app
and test bundle have built. For non-interactive CI, pass a mode-600 one-use file
through NILE_LAB_OPENROUTER_KEY_FILE. The runner removes that file before
reading it.
EOF
}

case "$MODE" in
    unit|ui|accessibility|visual|smoke|full|drive|installer) ;;
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if [[ "$PINNED_HERMES_REF" != "$EXPECTED_HERMES_REF" ]]; then
    printf 'Hermes pin does not match the Android compatibility contract.\n' >&2
    exit 2
fi
if [[ "$ALLOW_EXPENSIVE_MODEL" != "0" && "$ALLOW_EXPENSIVE_MODEL" != "1" ]]; then
    printf 'NILE_LAB_ALLOW_EXPENSIVE_MODEL must be 0 or 1.\n' >&2
    exit 2
fi

log() {
    printf '\n[test-lab] %s\n' "$*"
}

record_lane() {
    local lane="$1"
    shift
    local lane_started
    local lane_finished
    local lane_status
    lane_started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    log "Starting lane: $lane"
    if "$@"; then
        lane_status="passed"
    else
        lane_status="failed"
        LANE_FAILURES=$((LANE_FAILURES + 1))
    fi
    lane_finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\t%s\t%s\t%s\n' \
        "$lane" "$lane_status" "$lane_started" "$lane_finished" \
        >>"$RESULT_DIR/lane-results.tsv"
    log "Lane $lane: $lane_status"
    [[ "$lane_status" == "passed" ]]
}

block_lane() {
    local lane="$1"
    local reason="$2"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\tblocked\t%s\t%s\t%s\n' \
        "$lane" "$now" "$now" "$reason" >>"$RESULT_DIR/lane-results.tsv"
    LANE_FAILURES=$((LANE_FAILURES + 1))
    log "Lane $lane: blocked ($reason)"
}

lane_passed() {
    local lane="$1"
    awk -F '\t' -v lane="$lane" \
        '$1 == lane && $2 == "passed" { found = 1 } END { exit !found }' \
        "$RESULT_DIR/lane-results.tsv"
}

remove_key_handoff() {
    if [[ -n "$KEY_HANDOFF_FILE" && -e "$KEY_HANDOFF_FILE" ]]; then
        rm -f -- "$KEY_HANDOFF_FILE"
    fi
}

stop_hermes() {
    if [[ -n "$HERMES_PID" ]] && kill -0 "$HERMES_PID" 2>/dev/null; then
        kill "$HERMES_PID" 2>/dev/null || true
        for _ in $(seq 1 20); do
            if ! kill -0 "$HERMES_PID" 2>/dev/null; then
                break
            fi
            sleep 0.1
        done
        if kill -0 "$HERMES_PID" 2>/dev/null; then
            kill -9 "$HERMES_PID" 2>/dev/null || true
        fi
        wait "$HERMES_PID" 2>/dev/null || true
    fi
    HERMES_PID=""
}

stop_refresh_seed() {
    if [[ -n "$REFRESH_SEED_PID" ]] && \
        kill -0 "$REFRESH_SEED_PID" 2>/dev/null; then
        kill "$REFRESH_SEED_PID" 2>/dev/null || true
        wait "$REFRESH_SEED_PID" 2>/dev/null || true
    fi
    REFRESH_SEED_PID=""
}

collect_simulator_artifacts() {
    [[ -n "$SIMULATOR_UDID" ]] || return 0
    xcrun simctl io "$SIMULATOR_UDID" screenshot \
        "$RESULT_DIR/final-screen.png" >/dev/null 2>&1 || true
    xcrun simctl spawn "$SIMULATOR_UDID" log show \
        --style compact --last 30m \
        --predicate 'process == "Nile" OR process == "NileUITests-Runner"' \
        >"$RESULT_DIR/simulator-app.log" 2>/dev/null || true
}

collect_crash_reports() {
    local diagnostics_dir="$HOME/Library/Logs/DiagnosticReports"
    local crash_report
    local crash_count=0
    [[ -n "$DIAGNOSTIC_MARKER" && -f "$DIAGNOSTIC_MARKER" ]] || return 0
    [[ -d "$diagnostics_dir" ]] || return 0
    while IFS= read -r -d '' crash_report; do
        if (( crash_count == 0 )); then
            mkdir -p "$RESULT_DIR/crash-reports"
        fi
        cp "$crash_report" "$RESULT_DIR/crash-reports/"
        crash_count=$((crash_count + 1))
    done < <(
        find "$diagnostics_dir" -type f -newer "$DIAGNOSTIC_MARKER" \( \
            -name 'Nile*.ips' -o -name 'Nile*.crash' -o \
            -name 'NileUITests*.ips' -o -name 'NileUITests*.crash' \
        \) -print0
    )
    if (( crash_count > 0 )); then
        printf 'captured %d Nile crash report(s)\n' "$crash_count" \
            >"$RESULT_DIR/crash-reports/README.txt"
        return 1
    fi
}

scan_text_file_for_secret() {
    local file="$1"
    local secret="$2"
    [[ -n "$secret" && -f "$file" ]] || return 0
    if LC_ALL=C grep -aFq -- "$secret" "$file" 2>/dev/null; then
        printf 'secret scan found credential material in %s\n' "$file" >&2
        return 1
    fi
}

scan_retained_artifacts() {
    local contaminated=0
    local file
    local relative_path
    local removal_target
    local removal_log="$LAB_DIR/secret-bearing-artifacts.txt"
    : >"$removal_log"
    while IFS= read -r -d '' file; do
        if ! scan_text_file_for_secret "$file" "$HERMES_TOKEN" || \
            ! scan_text_file_for_secret "$file" "$LAB_OPENROUTER_API_KEY"; then
            contaminated=1
            removal_target="$file"
            if [[ "$file" == "$RESULT_DIR/"*.xcresult/* ]]; then
                removal_target="${file%%.xcresult/*}.xcresult"
            fi
            relative_path="${removal_target#"$RESULT_DIR"/}"
            printf '%s\n' "$relative_path" >>"$removal_log"
            if [[ -d "$removal_target" ]]; then
                rm -rf -- "$removal_target"
            else
                rm -f -- "$removal_target"
            fi
        fi
    done < <(find "$RESULT_DIR" -type f -print0)
    if (( contaminated == 0 )); then
        printf 'passed: no retained file contains the gateway token or provider key\n' \
            >"$RESULT_DIR/secret-scan.txt"
    else
        {
            printf 'failed: credential material was found; every affected artifact was removed\n'
            printf 'removed artifacts:\n'
            sort -u "$removal_log"
        } >"$RESULT_DIR/secret-scan.txt"
    fi
    return "$contaminated"
}

write_run_properties() {
    local finished_at
    finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    {
        printf 'mode=%s\n' "$MODE"
        printf 'status=%s\n' "$LAB_STATUS"
        printf 'started_at=%s\n' "$STARTED_AT"
        printf 'finished_at=%s\n' "$finished_at"
        printf 'android_ref=%s\n' "$PINNED_ANDROID_REF"
        printf 'android_tree=%s\n' "$PINNED_ANDROID_TREE"
        printf 'hermes_ref=%s\n' "$PINNED_HERMES_REF"
        printf 'app_bundle_id=com.niles.Nile\n'
        printf 'app_marketing_version=0.1.0\n'
        printf 'app_build_version=1\n'
        printf 'model_provider=openrouter\n'
        printf 'model=%s\n' "$MODEL_ID"
        printf 'model_switch_target=%s\n' "$MODEL_SWITCH_TARGET"
        printf 'simulator_name=%s\n' "$CANONICAL_SIMULATOR_NAME"
        printf 'simulator_runtime=%s\n' "$CANONICAL_RUNTIME_VERSION"
        printf 'simulator_udid=%s\n' "$SIMULATOR_UDID"
        printf 'xcode=%s\n' "$(xcodebuild -version | tr '\n' ';')"
        printf 'swift=%s\n' "$(swift --version 2>/dev/null | head -n 1)"
        printf 'xcodegen=%s\n' "$(xcodegen --version)"
    } >"$RESULT_DIR/run.properties"
}

cleanup() {
    local exit_status=$?
    trap - EXIT INT TERM
    remove_key_handoff
    collect_simulator_artifacts
    if ! collect_crash_reports; then
        exit_status=1
        LAB_STATUS="failed-crash-report"
    fi
    stop_refresh_seed
    stop_hermes
    if ! scan_retained_artifacts; then
        exit_status=1
        LAB_STATUS="failed-secret-scan"
    fi
    write_run_properties
    if [[ -n "$SIMULATOR_UDID" ]]; then
        xcrun simctl shutdown "$SIMULATOR_UDID" >/dev/null 2>&1 || true
        xcrun simctl delete "$SIMULATOR_UDID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$LAB_DIR" && -d "$LAB_DIR" && "${NILE_LAB_KEEP:-0}" != "1" ]]; then
        rm -rf -- "$LAB_DIR"
    fi
    printf '\nTest-lab artifacts: %s\n' "$RESULT_DIR"
    exit "$exit_status"
}
trap cleanup EXIT INT TERM

mkdir -p "$RESULT_ROOT"
mkdir "$RESULT_DIR"
printf 'lane\tstatus\tstarted_at\tfinished_at\tdetail\n' \
    >"$RESULT_DIR/lane-results.tsv"
LAB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nile-ios-test-lab.XXXXXX")"
LAB_HOME="$LAB_DIR/home"
HERMES_HOME="$LAB_DIR/hermes-home"
HERMES_INSTALL_DIR="$LAB_DIR/hermes-agent"
HERMES_WORKSPACE="$LAB_DIR/hermes-workspace"
mkdir -p "$LAB_HOME" "$HERMES_HOME" "$HERMES_WORKSPACE"
DIAGNOSTIC_MARKER="$LAB_DIR/diagnostic-marker"
: >"$DIAGNOSTIC_MARKER"

random_port() {
    python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

random_token() {
    python3 - <<'PY'
import secrets
print("nile-ios-test-" + secrets.token_hex(16))
PY
}

HERMES_PORT="$(random_port)"
HERMES_TOKEN="$(random_token)"

run_doctor() {
    "$ROOT_DIR/scripts/test-lab/doctor.sh" "$MODE" \
        >"$RESULT_DIR/doctor.log" 2>&1
}

create_simulator() {
    local simulator_name
    simulator_name="Nile Lab $RUN_ID"
    SIMULATOR_UDID="$(
        xcrun simctl create \
            "$simulator_name" "$SIMULATOR_DEVICE_TYPE" "$SIMULATOR_RUNTIME"
    )"
    [[ -n "$SIMULATOR_UDID" ]] || return 1
    xcrun simctl boot "$SIMULATOR_UDID"
    xcrun simctl bootstatus "$SIMULATOR_UDID" -b
    xcrun simctl status_bar "$SIMULATOR_UDID" override \
        --time '9:41' \
        --dataNetwork wifi \
        --wifiMode active \
        --wifiBars 3 \
        --cellularMode active \
        --cellularBars 4 \
        --batteryState charged \
        --batteryLevel 100
    xcrun simctl ui "$SIMULATOR_UDID" appearance dark
}

ensure_project_is_generated() {
    (
        cd "$ROOT_DIR"
        xcodegen generate
    ) >"$RESULT_DIR/xcodegen.log" 2>&1
}

run_xcodebuild() {
    local log_file="$1"
    shift
    (
        cd "$ROOT_DIR"
        xcodebuild -quiet "$@"
    ) 2>&1 | tee "$log_file"
}

export_result_summary() {
    local result_bundle="$1"
    local output_file="$2"
    xcrun xcresulttool get test-results summary \
        --path "$result_bundle" --compact >"$output_file"
}

run_unit_lane() {
    local derived_data="$LAB_DIR/DerivedData-unit"
    local result_bundle="$RESULT_DIR/unit.xcresult"
    local destination="platform=iOS Simulator,id=$SIMULATOR_UDID"
    run_xcodebuild "$RESULT_DIR/analyze.log" \
        -project Nile.xcodeproj \
        -scheme Nile \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$derived_data" \
        analyze || return 1
    run_xcodebuild "$RESULT_DIR/unit-tests.log" \
        -project Nile.xcodeproj \
        -scheme Nile \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$derived_data" \
        -resultBundlePath "$result_bundle" \
        test -only-testing:NileTests || return 1
    export_result_summary "$result_bundle" \
        "$RESULT_DIR/unit-summary.json" || return 1
    run_xcodebuild "$RESULT_DIR/release-build.log" \
        -project Nile.xcodeproj \
        -scheme Nile \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -derivedDataPath "$LAB_DIR/DerivedData-release" \
        CODE_SIGNING_ALLOWED=NO \
        SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
        build
}

run_ui_lane() {
    local result_bundle="$RESULT_DIR/ui.xcresult"
    run_xcodebuild "$RESULT_DIR/ui-tests.log" \
        -project Nile.xcodeproj \
        -scheme Nile \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
        -derivedDataPath "$LAB_DIR/DerivedData-ui" \
        -resultBundlePath "$result_bundle" \
        test -only-testing:NileUITests/NileLaunchTests || return 1
    export_result_summary "$result_bundle" \
        "$RESULT_DIR/ui-summary.json" || return 1
    mkdir -p "$RESULT_DIR/ui-attachments"
    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$RESULT_DIR/ui-attachments"
}

run_accessibility_lane() {
    local result_bundle="$RESULT_DIR/accessibility.xcresult"
    local test_status=0
    xcrun simctl ui "$SIMULATOR_UDID" \
        content_size accessibility-extra-large
    xcrun simctl ui "$SIMULATOR_UDID" content_size \
        >"$RESULT_DIR/accessibility-content-size.txt"
    if [[ "$(<"$RESULT_DIR/accessibility-content-size.txt")" != \
        "accessibility-extra-large" ]]; then
        printf 'Simulator did not apply the accessibility content size.\n' >&2
        xcrun simctl ui "$SIMULATOR_UDID" content_size large || true
        return 1
    fi
    run_xcodebuild "$RESULT_DIR/accessibility-tests.log" \
        -project Nile.xcodeproj \
        -scheme Nile \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
        -derivedDataPath "$LAB_DIR/DerivedData-accessibility" \
        -resultBundlePath "$result_bundle" \
        test -only-testing:NileUITests/NileAccessibilityTests \
        || test_status=$?
    xcrun simctl ui "$SIMULATOR_UDID" content_size large || {
        printf 'Could not restore the Simulator content size.\n' >&2
        return 1
    }
    (( test_status == 0 )) || return "$test_status"
    export_result_summary "$result_bundle" \
        "$RESULT_DIR/accessibility-summary.json" || return 1
    mkdir -p "$RESULT_DIR/accessibility-attachments"
    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$RESULT_DIR/accessibility-attachments"
}

run_visual_lane() {
    local result_bundle="$RESULT_DIR/visual.xcresult"
    local attachments="$RESULT_DIR/visual-attachments"
    local fixture
    local candidate_name
    local candidate_path
    local reference_path
    local runtime_manifest
    local failures=0
    "$ROOT_DIR/scripts/visual/test.sh" \
        >"$RESULT_DIR/visual-self-test.log" 2>&1 || return 1
    run_xcodebuild "$RESULT_DIR/visual-capture.log" \
        -project Nile.xcodeproj \
        -scheme Nile \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
        -derivedDataPath "$LAB_DIR/DerivedData-visual" \
        -resultBundlePath "$result_bundle" \
        test \
        -only-testing:NileUITests/NileLaunchTests/testPinnedAndroidOnboardingVisualFixtures \
        -only-testing:NileUITests/NileLaunchTests/testGatewayRemovalRequiresConfirmationAndMatchesPinnedAndroid \
        -only-testing:NileUITests/NileLaunchTests/testRunningTurnGatewaySwitchRequiresConfirmationAndMatchesPinnedAndroid \
        -only-testing:NileUITests/NileLaunchTests/testClarificationChoiceWaitsForExplicitContinue \
        -only-testing:NileUITests/NileLaunchTests/testHermesVoiceFixtureLoadsAppliesAndUpdatesGlobalSummary \
        -only-testing:NileUITests/NileLaunchTests/testTalkFixtureKeepsTranscriptPrivateAndDrivesPauseResumeEnd \
        -only-testing:NileUITests/NileLaunchTests/testPinnedAndroidBrandVisualFixtures \
        -only-testing:NileUITests/NileLaunchTests/testPinnedAndroidMediaVisualFixture \
        -only-testing:NileUITests/NileLaunchTests/testPinnedAndroidTranscriptSyntaxVisualFixture \
        -only-testing:NileUITests/NileLaunchTests/testPinnedAndroidAttachmentVisualFixture \
        -only-testing:NileUITests/NileLaunchTests/testPinnedAndroidModelPickerVisualFixture \
        -only-testing:NileUITests/NileLaunchTests/testPinnedAndroidRenameSessionVisualFixture \
        -only-testing:NileUITests/NileLaunchTests/testGoalQuickStartSheetPreservesComposerDraftAndBudget \
        -only-testing:NileUITests/NileLaunchTests/testActiveGoalCardIsCompactAndDetailsExpand \
        -only-testing:NileUITests/NileLaunchTests/testPinnedAndroidDelegationMixedVisualFixture \
        -only-testing:NileUITests/NileLaunchTests/testContextBreakdownShowsCurrentUsageComposition \
        -only-testing:NileUITests/NileLaunchTests/testGatewayStatsShowsProfileActivityAndHeatmap \
        || return 1
    mkdir -p "$attachments"
    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$attachments" || return 1
    for fixture in \
        onboarding-clean \
        onboarding-form \
        gateway-removal-dialog \
        gateway-switch-dialog \
        blocking-clarification \
        hermes-voice-settings \
        talk-listening \
        brand-chat \
        brand-sessions \
        media \
        transcript-syntax-tail \
        attachment-composer-and-media-cards \
        model-picker-app-popup \
        rename-session-dialog \
        goal-quick-start-sheet \
        goal-active-card \
        goal-active-details-sheet \
        delegation-mixed \
        context-breakdown-sheet \
        gateway-stats-sheet; do
        candidate_name="$(
            jq -r --arg prefix "android-parity-${fixture}_" '
                [
                  .[].attachments[]
                  | select(
                      .suggestedHumanReadableName
                      | startswith($prefix)
                    )
                  | .exportedFileName
                ][0] // empty
            ' "$attachments/manifest.json"
        )"
        if [[ -z "$candidate_name" ]]; then
            printf 'visual capture did not export %s\n' "$fixture" >&2
            failures=$((failures + 1))
            continue
        fi
        candidate_path="$attachments/$candidate_name"
        if [[ "$fixture" == "media" ]]; then
            reference_path="$ROOT_DIR/.reference/android/docs/screenshots/nile-media.png"
        else
            reference_path="$ROOT_DIR/scripts/visual/baselines/android/${fixture}.png"
        fi
        runtime_manifest="$RESULT_DIR/${fixture}-runtime.json"
        cp "$ROOT_DIR/scripts/visual/manifests/${fixture/onboarding-clean/onboarding}.json" \
            "$runtime_manifest"
        plutil -replace reference.path \
            -string "$reference_path" "$runtime_manifest"
        plutil -replace candidate.path \
            -string "$candidate_path" "$runtime_manifest"
        if ! "$ROOT_DIR/scripts/visual/compare.sh" \
            "$runtime_manifest" \
            --output "$RESULT_DIR/visual-${fixture}"; then
            failures=$((failures + 1))
        fi
    done
    (( failures == 0 ))
}

install_hermes() {
    local installer_source="$LAB_DIR/hermes-installer-source"
    local no_sudo_dir="$LAB_DIR/no-sudo"
    local installed_ref
    log "Fetching fresh Hermes installer source at $PINNED_HERMES_REF"
    git clone --quiet --filter=blob:none \
        https://github.com/NousResearch/hermes-agent.git "$installer_source" \
        || return 1
    git -C "$installer_source" checkout --quiet "$PINNED_HERMES_REF" \
        || return 1
    [[ "$(git -C "$installer_source" rev-parse HEAD)" == "$PINNED_HERMES_REF" ]] \
        || return 1
    git -C "$installer_source" diff --quiet --ignore-submodules -- || return 1
    git -C "$installer_source" diff --cached --quiet --ignore-submodules -- \
        || return 1
    mkdir -p "$no_sudo_dir"
    printf '#!/bin/sh\nexit 1\n' >"$no_sudo_dir/sudo"
    chmod +x "$no_sudo_dir/sudo"
    log "Installing fresh unmodified pinned Hermes into the disposable lab"
    env \
        HOME="$LAB_HOME" \
        HERMES_HOME="$HERMES_HOME" \
        HERMES_INSTALL_DIR="$HERMES_INSTALL_DIR" \
        GIT_CONFIG_GLOBAL=/dev/null \
        GIT_TERMINAL_PROMPT=0 \
        PATH="$no_sudo_dir:$PATH" \
        UV_CACHE_DIR="$LAB_DIR/uv-cache" \
        NPM_CONFIG_CACHE="$LAB_DIR/npm-cache" \
        bash "$installer_source/scripts/install.sh" \
            --dir "$HERMES_INSTALL_DIR" \
            --hermes-home "$HERMES_HOME" \
            --commit "$PINNED_HERMES_REF" \
            --skip-setup \
            --skip-browser \
            --no-skills \
            --non-interactive </dev/null \
        >"$RESULT_DIR/hermes-install.log" 2>&1 || return 1
    HERMES_BIN="$HERMES_INSTALL_DIR/venv/bin/hermes"
    HERMES_PYTHON="$HERMES_INSTALL_DIR/venv/bin/python"
    [[ -x "$HERMES_BIN" && -x "$HERMES_PYTHON" ]] || return 1
    installed_ref="$(git -C "$HERMES_INSTALL_DIR" rev-parse HEAD)"
    [[ "$installed_ref" == "$PINNED_HERMES_REF" ]] || return 1
    git -C "$HERMES_INSTALL_DIR" diff --quiet --ignore-submodules -- || return 1
    git -C "$HERMES_INSTALL_DIR" diff --cached --quiet --ignore-submodules -- \
        || return 1
    grep -Fq 'Main package installed (hash-verified via uv.lock)' \
        "$RESULT_DIR/hermes-install.log" || return 1
    HERMES_HOME="$HERMES_HOME" "$HERMES_PYTHON" \
        -c 'import hermes_state' || return 1
    "$HERMES_BIN" --version >"$RESULT_DIR/hermes-version.txt"
}

discover_models() {
    local catalog="$LAB_DIR/openrouter-models.json"
    curl --fail --silent --show-error --max-time 20 \
        "$OPENROUTER_MODELS_URL" >"$catalog" || return 1
    python3 - "$catalog" "$MODEL_ID" "$MODEL_SWITCH_TARGET" \
        "$ALLOW_EXPENSIVE_MODEL" >"$RESULT_DIR/model-selection.txt" <<'PY'
import json
import sys

catalog_path, primary, switch, allow_expensive = sys.argv[1:]
with open(catalog_path, encoding="utf-8") as handle:
    rows = json.load(handle).get("data", [])
by_id = {row.get("id"): row for row in rows}
for label, model_id in (("primary", primary), ("switch", switch)):
    row = by_id.get(model_id)
    if row is None:
        raise SystemExit(f"{label} model is absent from the public OpenRouter catalog: {model_id}")
    pricing = row.get("pricing") or {}
    input_price = float(pricing.get("prompt") or 0) * 1_000_000
    output_price = float(pricing.get("completion") or 0) * 1_000_000
    if allow_expensive != "1" and (input_price > 0.50 or output_price > 2.00):
        raise SystemExit(
            f"{label} model exceeds the lab price cap: "
            f"${input_price:.4f}/M input, ${output_price:.4f}/M output"
        )
    print(
        f"{label}={model_id} "
        f"input_per_million={input_price:.4f} "
        f"output_per_million={output_price:.4f}"
    )
PY
}

write_hermes_config() {
    {
        printf 'model:\n'
        printf '  default: "%s"\n' "$MODEL_ID"
        printf '  provider: openrouter\n'
        printf '  base_url: "https://openrouter.ai/api/v1"\n'
        printf '  api_mode: chat_completions\n'
        printf '  max_tokens: 256\n\n'
        printf 'agent:\n'
        printf '  max_turns: 3\n'
        printf '  reasoning_effort: none\n'
        printf '  disabled_toolsets:\n'
        printf '    - browser\n'
        printf '    - cronjob\n'
        printf '    - file\n'
        printf '    - image_gen\n'
        printf '    - memory\n'
        printf '    - search\n'
        printf '    - session_search\n'
        printf '    - skills\n'
        printf '    - skills_hub\n'
        printf '    - terminal\n'
        printf '    - tts\n'
        printf '    - vision\n'
        printf '    - web\n\n'
        printf 'platform_toolsets:\n'
        printf '  cli: [todo, no_mcp]\n\n'
        printf 'terminal:\n'
        printf '  cwd: "%s"\n\n' "$HERMES_WORKSPACE"
        printf 'compression:\n'
        printf '  enabled: false\n\n'
        printf 'security:\n'
        printf '  tirith_enabled: false\n\n'
        printf 'memory:\n'
        printf '  memory_enabled: false\n'
        printf '  user_profile_enabled: false\n'
    } >"$HERMES_HOME/config.yaml"
    : >"$HERMES_HOME/.env"
    chmod 600 "$HERMES_HOME/.env"
}

acquire_openrouter_key() {
    local entered_key=""
    local extra_line=""
    local key_mode=""
    if [[ -n "$KEY_HANDOFF_FILE" ]]; then
        [[ -f "$KEY_HANDOFF_FILE" && ! -L "$KEY_HANDOFF_FILE" ]] || {
            printf 'OpenRouter key handoff must be a non-symlink regular file.\n' >&2
            return 1
        }
        key_mode="$(stat -f '%Lp' "$KEY_HANDOFF_FILE" 2>/dev/null || true)"
        [[ "$key_mode" == "600" ]] || {
            printf 'OpenRouter key handoff must have mode 600.\n' >&2
            return 1
        }
        exec 9<"$KEY_HANDOFF_FILE"
        rm -f -- "$KEY_HANDOFF_FILE"
        KEY_HANDOFF_FILE=""
        IFS= read -r entered_key <&9 || true
        if IFS= read -r extra_line <&9; then
            exec 9<&-
            printf 'OpenRouter key handoff must contain exactly one line.\n' >&2
            return 1
        fi
        exec 9<&-
    elif [[ -r /dev/tty && -w /dev/tty ]]; then
        printf 'OpenRouter API key: ' >/dev/tty
        IFS= read -r -s entered_key </dev/tty || {
            printf '\nCould not read the OpenRouter API key.\n' >/dev/tty
            return 1
        }
        printf '\n' >/dev/tty
    else
        printf 'Real-Hermes lanes require a controlling terminal or mode-600 key handoff.\n' >&2
        return 1
    fi
    if [[ ! "$entered_key" =~ ^sk-or-v1-[A-Za-z0-9_-]{20,}$ ]]; then
        entered_key=""
        printf 'OpenRouter API key has an unexpected format.\n' >&2
        return 1
    fi
    LAB_OPENROUTER_API_KEY="$entered_key"
    entered_key=""
}

start_hermes() {
    log "Starting isolated Hermes dashboard on 127.0.0.1:$HERMES_PORT"
    (
        cd "$HERMES_WORKSPACE"
        exec env \
            HOME="$LAB_HOME" \
            HERMES_HOME="$HERMES_HOME" \
            HERMES_DASHBOARD_SESSION_TOKEN="$HERMES_TOKEN" \
            HERMES_ENVIRONMENT_HINT='Nile disposable iOS test. Reply only; do not use tools.' \
            OPENROUTER_API_KEY="$LAB_OPENROUTER_API_KEY" \
            HTTP_PROXY=http://127.0.0.1:9 \
            HTTPS_PROXY=http://127.0.0.1:9 \
            ALL_PROXY=http://127.0.0.1:9 \
            NO_PROXY=127.0.0.1,localhost,::1,openrouter.ai \
            http_proxy=http://127.0.0.1:9 \
            https_proxy=http://127.0.0.1:9 \
            all_proxy=http://127.0.0.1:9 \
            no_proxy=127.0.0.1,localhost,::1,openrouter.ai \
            "$HERMES_BIN" serve --host 127.0.0.1 --port "$HERMES_PORT"
    ) >"$RESULT_DIR/hermes-serve.log" 2>&1 &
    HERMES_PID=$!
    for _ in $(seq 1 120); do
        if curl --fail --silent --max-time 2 \
            "http://127.0.0.1:$HERMES_PORT/api/status" >/dev/null; then
            return 0
        fi
        if ! kill -0 "$HERMES_PID" 2>/dev/null; then
            return 1
        fi
        sleep 1
    done
    return 1
}

create_cli_fixture() {
    local prompt
    prompt='Concatenate NILE-, CLI-, FIXTURE-, and OK. Reply only with the result.'
    (
        cd "$HERMES_WORKSPACE"
        env \
            HOME="$LAB_HOME" \
            HERMES_HOME="$HERMES_HOME" \
            OPENROUTER_API_KEY="$LAB_OPENROUTER_API_KEY" \
            NO_PROXY=127.0.0.1,localhost,::1,openrouter.ai \
            "$HERMES_BIN" chat \
                --query "$prompt" \
                --quiet \
                --source cli \
                --toolsets todo \
                --ignore-rules
    ) >"$RESULT_DIR/cli-fixture.log" 2>&1 || return 1
    grep -Fq "$CLI_MARKER" "$RESULT_DIR/cli-fixture.log" || return 1
    CLI_SESSION_ID="$(
        HERMES_HOME="$HERMES_HOME" "$HERMES_PYTHON" - "$CLI_MARKER" <<'PY'
import sys
from hermes_state import SessionDB

marker = sys.argv[1]
db = SessionDB()
try:
    sessions = db.list_sessions_rich(
        source="cli",
        limit=1,
        order_by_last_active=True,
    )
    if len(sessions) != 1:
        raise SystemExit("Hermes did not store one newest CLI fixture session")
    session_id = str(sessions[0].get("id") or "")
    messages = db.get_messages(session_id)
    if not session_id or not messages:
        raise SystemExit("Hermes stored an invalid CLI fixture session")
    if marker not in str(messages[-1].get("content") or ""):
        raise SystemExit("Newest CLI response did not contain the fixture marker")
finally:
    db.close()
print(session_id)
PY
    )"
    [[ -n "$CLI_SESSION_ID" ]]
}

seed_persisted_refresh_after_initial_read() {
    local refresh_marker="NILE-PERSISTED-REFRESH-OK"
    local observed=0
    for _ in $(seq 1 600); do
        if grep -Eq \
            '"GET /api/sessions/.+/messages[^"]* HTTP/[^"]+" 200' \
            "$RESULT_DIR/hermes-serve.log" 2>/dev/null; then
            observed=1
            break
        fi
        sleep 0.2
    done
    (( observed == 1 )) || return 1
    HERMES_HOME="$HERMES_HOME" "$HERMES_PYTHON" - \
        "$CLI_SESSION_ID" "$refresh_marker" <<'PY'
import sys
from hermes_state import SessionDB

session_id, marker = sys.argv[1:]
db = SessionDB()
try:
    before = db.get_messages(session_id)
    db.append_message(session_id, "assistant", marker, observed=True)
    after = db.get_messages(session_id)
    if len(after) != len(before) + 1:
        raise SystemExit("persisted refresh fixture was not appended exactly once")
    if after[-1].get("content") != marker or not bool(after[-1].get("observed")):
        raise SystemExit("persisted refresh fixture row was invalid")
finally:
    db.close()
PY
}

build_real_hermes_tests() {
    run_xcodebuild "$RESULT_DIR/smoke-build.log" \
        -project Nile.xcodeproj \
        -scheme Nile \
        -configuration Debug \
        -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
        -derivedDataPath "$LAB_DIR/DerivedData-smoke" \
        build-for-testing
}

run_real_hermes_phase() {
    local phase="$1"
    local test_name="$2"
    local result_bundle="$RESULT_DIR/smoke-$phase.xcresult"
    (
        cd "$ROOT_DIR"
        env \
            NILE_LAB_REAL_HERMES=1 \
            NILE_LAB_PHASE="$phase" \
            NILE_LAB_GATEWAY_URL="http://127.0.0.1:$HERMES_PORT" \
            NILE_LAB_GATEWAY_TOKEN="$HERMES_TOKEN" \
            NILE_LAB_CLI_MARKER="$CLI_MARKER" \
            NILE_LAB_MODEL_SWITCH_TARGET="$MODEL_SWITCH_TARGET" \
            NILE_LAB_GOAL_PROGRESS_MARKER="$GOAL_PROGRESS_MARKER" \
            NILE_LAB_GOAL_DONE_MARKER="$GOAL_DONE_MARKER" \
            NILE_LAB_GOAL_MAX_TURNS="$GOAL_MAX_TURNS" \
            xcodebuild -quiet \
                -project Nile.xcodeproj \
                -scheme Nile \
                -configuration Debug \
                -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
                -derivedDataPath "$LAB_DIR/DerivedData-smoke" \
                -resultBundlePath "$result_bundle" \
                test-without-building \
                "-only-testing:NileUITests/NileRealHermesTests/$test_name"
    ) >"$RESULT_DIR/smoke-$phase.log" 2>&1 || return 1
    export_result_summary "$result_bundle" \
        "$RESULT_DIR/smoke-$phase-summary.json" || return 1
    mkdir -p "$RESULT_DIR/smoke-$phase-attachments"
    xcrun xcresulttool export attachments \
        --path "$result_bundle" \
        --output-path "$RESULT_DIR/smoke-$phase-attachments" || return 1
    # The gateway token is provided to the UI-test process. XCTest normally
    # masks secure-field input, but a raw result bundle is not a publishable
    # contract for a credentialed lane. Keep its exported summary and
    # attachments, then destroy the raw bundle before the all-file secret scan.
    rm -rf -- "$result_bundle"
}

run_real_hermes_tests() {
    seed_persisted_refresh_after_initial_read \
        >"$RESULT_DIR/persisted-refresh-seed.log" 2>&1 &
    REFRESH_SEED_PID=$!
    run_real_hermes_phase \
        journey \
        testProductionGatewayJourneyThroughClaimControlsTurnStopAndGoal \
        || return 1
    wait "$REFRESH_SEED_PID" || return 1
    REFRESH_SEED_PID=""
    cp "$RESULT_DIR/hermes-serve.log" \
        "$RESULT_DIR/hermes-serve-journey.log" || return 1
    stop_hermes
    run_real_hermes_phase \
        offline \
        testPersistedGatewayFailsClosedWhileHermesIsOffline \
        || return 1
    start_hermes || return 1
    run_real_hermes_phase \
        reconnect \
        testRelaunchReconnectsAndRestoresClaimedSession \
        || return 1
    cp "$RESULT_DIR/hermes-serve.log" \
        "$RESULT_DIR/hermes-serve-reconnect.log" || return 1
}

prepare_real_hermes() {
    install_hermes || return 1
    discover_models || return 1
    write_hermes_config || return 1
    acquire_openrouter_key || return 1
    start_hermes || return 1
    create_cli_fixture
}

prepare_xcode_lanes() {
    ensure_project_is_generated || return 1
    create_simulator
}

record_lane doctor run_doctor || true
if ! lane_passed doctor; then
    block_lane setup "doctor failed"
else
    case "$MODE" in
        installer)
            record_lane hermes-installer install_hermes || true
            ;;
        unit)
            if record_lane setup prepare_xcode_lanes; then
                record_lane unit run_unit_lane || true
            else
                block_lane unit "Xcode project or disposable Simulator setup failed"
            fi
            ;;
        ui)
            if record_lane setup prepare_xcode_lanes; then
                record_lane ui run_ui_lane || true
            else
                block_lane ui "Xcode project or disposable Simulator setup failed"
            fi
            ;;
        accessibility)
            if record_lane setup prepare_xcode_lanes; then
                record_lane accessibility run_accessibility_lane || true
            else
                block_lane accessibility \
                    "Xcode project or disposable Simulator setup failed"
            fi
            ;;
        visual)
            if record_lane setup prepare_xcode_lanes; then
                record_lane visual run_visual_lane || true
            else
                block_lane visual "Xcode project or disposable Simulator setup failed"
            fi
            ;;
        smoke)
            if record_lane setup prepare_xcode_lanes; then
                if record_lane smoke-build build_real_hermes_tests; then
                    if record_lane hermes-fixture prepare_real_hermes; then
                        record_lane smoke run_real_hermes_tests || true
                    else
                        block_lane smoke "fresh pinned Hermes fixture failed"
                    fi
                else
                    block_lane hermes-fixture "production app or test bundle did not build"
                    block_lane smoke "production app or test bundle did not build"
                fi
            else
                block_lane smoke-build "Xcode project or disposable Simulator setup failed"
                block_lane hermes-fixture "Xcode project or disposable Simulator setup failed"
                block_lane smoke "Xcode project or disposable Simulator setup failed"
            fi
            ;;
        full)
            if record_lane setup prepare_xcode_lanes; then
                record_lane unit run_unit_lane || true
                record_lane ui run_ui_lane || true
                record_lane visual run_visual_lane || true
                record_lane accessibility run_accessibility_lane || true
                if record_lane smoke-build build_real_hermes_tests; then
                    if lane_passed unit && lane_passed ui && \
                        lane_passed visual && \
                        lane_passed accessibility; then
                        if record_lane hermes-fixture prepare_real_hermes; then
                            record_lane smoke run_real_hermes_tests || true
                        else
                            block_lane smoke "fresh pinned Hermes fixture failed"
                        fi
                    else
                        block_lane hermes-fixture \
                            "unit, UI, accessibility, or visual prerequisite failed"
                        block_lane smoke \
                            "unit, UI, accessibility, or visual prerequisite failed"
                    fi
                else
                    block_lane hermes-fixture "production app or test bundle did not build"
                    block_lane smoke "production app or test bundle did not build"
                fi
            else
                for lane in unit ui accessibility visual smoke-build \
                    hermes-fixture smoke; do
                    block_lane "$lane" "Xcode project or disposable Simulator setup failed"
                done
            fi
            ;;
        drive)
            if record_lane setup prepare_xcode_lanes && \
                record_lane smoke-build build_real_hermes_tests && \
                record_lane hermes-fixture prepare_real_hermes; then
                app_path="$LAB_DIR/DerivedData-smoke/Build/Products/Debug-iphonesimulator/Nile.app"
                xcrun simctl install "$SIMULATOR_UDID" "$app_path"
                xcrun simctl launch "$SIMULATOR_UDID" com.niles.Nile
                open -a Simulator
                printf '\nDisposable test drive is ready.\n'
                printf '  Simulator: %s\n' "$SIMULATOR_UDID"
                printf '  Dashboard URL: http://127.0.0.1:%s\n' "$HERMES_PORT"
                printf '  Session token: %s\n' "$HERMES_TOKEN"
                printf '  Model: %s\n' "$MODEL_ID"
                printf 'Press Ctrl-C to destroy the lab.\n'
                while true; do
                    sleep 30
                done
            else
                block_lane drive "setup, build, or fresh pinned Hermes fixture failed"
            fi
            ;;
    esac
fi

if (( LANE_FAILURES > 0 )); then
    LAB_STATUS="failed"
    exit 1
fi
LAB_STATUS="passed"
