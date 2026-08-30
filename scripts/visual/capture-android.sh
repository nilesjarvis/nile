#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
sdk_root=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}}
adb_bin="$sdk_root/platform-tools/adb"
avdmanager_bin="$sdk_root/cmdline-tools/latest/bin/avdmanager"
emulator_bin="$sdk_root/emulator/emulator"
system_image="system-images;android-35;google_apis;arm64-v8a"
apk_path="$repo_root/.reference/android/app/build/outputs/apk/debug/app-debug.apk"
expected_apk_sha="0555e430eb6d06708a43cc04d8dc669fd6e40de5f5789ccc2b2aae431bd6400d"
android_commit="bd5451da891f2d886b9bc35f8ea67d6920df1d98"
android_tree="3b954e5844f05276d34aaee34a7d3f69169ef9f5"
capture_patch="$repo_root/scripts/visual/android-model-picker-test.patch"
run_id=$(date -u +%Y%m%dT%H%M%SZ)-$$
lab_root="$repo_root/build/android-visual-lab-$run_id"
output_dir="$repo_root/build/android-visual-captures/$run_id"
avd_name="NileVisual-$run_id"
emulator_pid=
serial=

usage() {
    echo "usage: $0 [--output DIRECTORY]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --output)
            [ "$#" -ge 2 ] || {
                usage >&2
                exit 64
            }
            output_dir=$2
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 64
            ;;
    esac
done

cleanup() {
    if [ -n "$serial" ]; then
        "$adb_bin" -s "$serial" emu kill >/dev/null 2>&1 || true
    fi
    if [ -n "$emulator_pid" ]; then
        wait "$emulator_pid" 2>/dev/null || true
    fi
    if [ -f "$lab_root/emulator.log" ] && [ -d "$output_dir" ]; then
        cp "$lab_root/emulator.log" "$output_dir/emulator.log"
    fi
    case "$lab_root" in
        "$repo_root"/build/android-visual-lab-*)
            rm -rf -- "$lab_root"
            ;;
    esac
}
trap cleanup EXIT INT TERM

for required in "$adb_bin" "$avdmanager_bin" "$emulator_bin"; do
    [ -x "$required" ] || {
        echo "missing Android tool: $required" >&2
        exit 69
    }
done
[ -f "$apk_path" ] || {
    echo "missing pinned APK: $apk_path" >&2
    exit 66
}
[ -f "$capture_patch" ] || {
    echo "missing Android capture patch: $capture_patch" >&2
    exit 66
}
actual_apk_sha=$(shasum -a 256 "$apk_path" | awk '{print $1}')
[ "$actual_apk_sha" = "$expected_apk_sha" ] || {
    echo "pinned APK hash mismatch: $actual_apk_sha" >&2
    exit 65
}
"$sdk_root/cmdline-tools/latest/bin/sdkmanager" --list_installed \
    | rg -F "$system_image" >/dev/null || {
        echo "missing Android system image: $system_image" >&2
        exit 69
    }

mkdir -p "$lab_root/avd" "$lab_root/android-user" "$output_dir"
export ANDROID_AVD_HOME="$lab_root/avd"
export ANDROID_USER_HOME="$lab_root/android-user"

test_source="$lab_root/android-test-source"
git clone --quiet --no-hardlinks \
    "$repo_root/.reference/android" "$test_source"
[ "$(git -C "$test_source" rev-parse HEAD)" = "$android_commit" ] || {
    echo "Android test source commit mismatch" >&2
    exit 65
}
[ "$(git -C "$test_source" rev-parse HEAD^{tree})" = "$android_tree" ] || {
    echo "Android test source tree mismatch" >&2
    exit 65
}
git -C "$test_source" apply --check "$capture_patch"
git -C "$test_source" apply "$capture_patch"
patched_files=$(git -C "$test_source" diff --name-only)
[ "$patched_files" = "app/src/androidTest/java/com/niles/app/ComposerBlockingPromptUiTest.kt
app/src/androidTest/java/com/niles/app/GatewayManagementUiTest.kt
app/src/androidTest/java/com/niles/app/GoalUiTest.kt
app/src/androidTest/java/com/niles/app/HermesVoiceUiTest.kt
app/src/androidTest/java/com/niles/app/ModelPickerUiTest.kt
app/src/androidTest/java/com/niles/app/SessionSourceLabelTest.kt
app/src/androidTest/java/com/niles/app/TalkModeUiTest.kt
app/src/androidTest/java/com/niles/app/TranscriptRowsUiTest.kt" ] || {
    echo "test-only patch unexpectedly changed production source" >&2
    exit 65
}
(
    cd "$test_source"
    ANDROID_HOME="$sdk_root" \
        ANDROID_SDK_ROOT="$sdk_root" \
        ./gradlew --no-daemon \
            :app:assembleDebug \
            :app:assembleDebugAndroidTest
) >"$output_dir/android-test-build.log" 2>&1
lab_apk="$test_source/app/build/outputs/apk/debug/app-debug.apk"
test_apk="$test_source/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
[ -f "$lab_apk" ] || {
    echo "Android app-under-test APK was not produced" >&2
    exit 66
}
[ -f "$test_apk" ] || {
    echo "Android model-picker test APK was not produced" >&2
    exit 66
}
lab_apk_sha=$(shasum -a 256 "$lab_apk" | awk '{print $1}')
test_apk_sha=$(shasum -a 256 "$test_apk" | awk '{print $1}')

printf 'no\n' | "$avdmanager_bin" create avd \
    --force \
    --name "$avd_name" \
    --package "$system_image" \
    --device pixel_6 >/dev/null

port=5582
while "$adb_bin" devices | rg -q "^emulator-$port[[:space:]]"; do
    port=$((port + 2))
done
serial="emulator-$port"

"$emulator_bin" "@$avd_name" \
    -port "$port" \
    -wipe-data \
    -no-snapshot \
    -no-window \
    -no-audio \
    -no-boot-anim \
    -gpu swiftshader_indirect \
    >"$lab_root/emulator.log" 2>&1 &
emulator_pid=$!

wait_for_boot() {
    deadline=$(( $(date +%s) + 180 ))
    while :; do
        boot_completed=$(
            "$adb_bin" -s "$serial" shell getprop sys.boot_completed \
                2>/dev/null | tr -d '\r' || true
        )
        [ "$boot_completed" = "1" ] && break
        [ "$(date +%s)" -lt "$deadline" ] || {
            echo "Android emulator did not boot within 180 seconds" >&2
            exit 70
        }
        sleep 1
    done
}

wait_for_boot
"$adb_bin" -s "$serial" shell wm size 1206x2478 >/dev/null
"$adb_bin" -s "$serial" shell wm density 480 >/dev/null
"$adb_bin" -s "$serial" shell settings put system font_scale 1.0
"$adb_bin" -s "$serial" shell settings put secure ui_night_mode 2
"$adb_bin" -s "$serial" shell cmd uimode night yes >/dev/null
"$adb_bin" -s "$serial" shell settings put global window_animation_scale 0
"$adb_bin" -s "$serial" shell settings put global transition_animation_scale 0
"$adb_bin" -s "$serial" shell settings put global animator_duration_scale 0
"$adb_bin" -s "$serial" shell settings put system accelerometer_rotation 0
"$adb_bin" -s "$serial" shell settings put system user_rotation 0
"$adb_bin" -s "$serial" install -r "$lab_apk" >/dev/null
"$adb_bin" -s "$serial" shell pm clear com.niles >/dev/null
"$adb_bin" -s "$serial" shell am start -W \
    -n com.niles/.MainActivity >/dev/null

wait_for_text() {
    expected=$1
    timeout_at=$(( $(date +%s) + 30 ))
    while :; do
        "$adb_bin" -s "$serial" shell uiautomator dump \
            /sdcard/window.xml >/dev/null 2>&1 || true
        if "$adb_bin" -s "$serial" shell cat /sdcard/window.xml \
            2>/dev/null | rg -F "$expected" >/dev/null; then
            return
        fi
        [ "$(date +%s)" -lt "$timeout_at" ] || {
            echo "timed out waiting for Android text: $expected" >&2
            exit 70
        }
        sleep 1
    done
}

capture() {
    name=$1
    "$adb_bin" -s "$serial" exec-out screencap -p \
        >"$output_dir/$name.png"
    "$adb_bin" -s "$serial" shell uiautomator dump \
        "/sdcard/$name.xml" >/dev/null
    "$adb_bin" -s "$serial" pull \
        "/sdcard/$name.xml" "$output_dir/$name.xml" >/dev/null
    width=$(sips -g pixelWidth "$output_dir/$name.png" \
        | awk '/pixelWidth/ {print $2}')
    height=$(sips -g pixelHeight "$output_dir/$name.png" \
        | awk '/pixelHeight/ {print $2}')
    [ "$width" = "1206" ] && [ "$height" = "2478" ] || {
        echo "$name capture was ${width}x${height}, expected 1206x2478" >&2
        exit 65
    }
}

wait_for_text 'Add gateway'
window_insets=$("$adb_bin" -s "$serial" shell dumpsys window displays)
printf '%s\n' "$window_insets" >"$output_dir/window-insets.txt"
printf '%s\n' "$window_insets" \
    | rg -F 'type=statusBars frame=[0,0][1206,72]' >/dev/null || {
        echo "unexpected Android status-bar inset" >&2
        exit 65
    }
printf '%s\n' "$window_insets" \
    | rg -F 'type=navigationBars frame=[0,2406][1206,2478]' >/dev/null || {
        echo "unexpected Android navigation-bar inset" >&2
        exit 65
    }
capture onboarding-clean
"$adb_bin" -s "$serial" shell input tap 603 1014
wait_for_text 'Connect insecurely'
capture onboarding-form

"$adb_bin" -s "$serial" install -r "$test_apk" >/dev/null
checkpoint_dir="/sdcard/Android/data/com.niles/files/test-lab-checkpoints"
"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.GatewayManagementUiTest#capturesActiveGatewayRemovalConfirmation' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/gateway-removal-dialog-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/gateway-removal-dialog.png" \
    "$output_dir/gateway-removal-dialog.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/gateway-removal-dialog-semantics.txt" \
    "$output_dir/gateway-removal-dialog-semantics.txt" >/dev/null
gateway_removal_width=$(sips -g pixelWidth \
    "$output_dir/gateway-removal-dialog.png" \
    | awk '/pixelWidth/ {print $2}')
gateway_removal_height=$(sips -g pixelHeight \
    "$output_dir/gateway-removal-dialog.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$gateway_removal_width" = "1206" ] \
    && [ "$gateway_removal_height" = "2478" ] || {
        echo "gateway-removal capture was ${gateway_removal_width}x${gateway_removal_height}" >&2
        exit 65
    }
rg -F "Text = '[Remove Home Hermes?]'" \
    "$output_dir/gateway-removal-dialog-semantics.txt" >/dev/null
rg -F "Text = '[Remove gateway]'" \
    "$output_dir/gateway-removal-dialog-semantics.txt" >/dev/null
rg -F "Text = '[Cancel]'" \
    "$output_dir/gateway-removal-dialog-semantics.txt" >/dev/null
rg -F "Conversations remain on Hermes." \
    "$output_dir/gateway-removal-dialog-semantics.txt" >/dev/null
rg -F "Any Hermes turn already running may continue without Nile following it." \
    "$output_dir/gateway-removal-dialog-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.GatewayManagementUiTest#runningTurnGatewaySwitchRequiresExplicitConfirmation' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/gateway-switch-dialog-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/gateway-switch-dialog.png" \
    "$output_dir/gateway-switch-dialog.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/gateway-switch-dialog-semantics.txt" \
    "$output_dir/gateway-switch-dialog-semantics.txt" >/dev/null
gateway_switch_width=$(sips -g pixelWidth \
    "$output_dir/gateway-switch-dialog.png" \
    | awk '/pixelWidth/ {print $2}')
gateway_switch_height=$(sips -g pixelHeight \
    "$output_dir/gateway-switch-dialog.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$gateway_switch_width" = "1206" ] \
    && [ "$gateway_switch_height" = "2478" ] || {
        echo "gateway-switch capture was ${gateway_switch_width}x${gateway_switch_height}" >&2
        exit 65
    }
rg -F "Text = '[Switch to Lab Hermes?]'" \
    "$output_dir/gateway-switch-dialog-semantics.txt" >/dev/null
rg -F "Text = '[Switch gateway]'" \
    "$output_dir/gateway-switch-dialog-semantics.txt" >/dev/null
rg -F "Text = '[Stay here]'" \
    "$output_dir/gateway-switch-dialog-semantics.txt" >/dev/null
rg -F "A Hermes turn is still running on the current gateway." \
    "$output_dir/gateway-switch-dialog-semantics.txt" >/dev/null
rg -F "Nile will no longer follow it." \
    "$output_dir/gateway-switch-dialog-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.ComposerBlockingPromptUiTest#capturesClarificationPromptForCrossPlatformParity' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/blocking-clarification-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/blocking-clarification.png" \
    "$output_dir/blocking-clarification.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/blocking-clarification-semantics.txt" \
    "$output_dir/blocking-clarification-semantics.txt" >/dev/null
blocking_clarification_width=$(sips -g pixelWidth \
    "$output_dir/blocking-clarification.png" \
    | awk '/pixelWidth/ {print $2}')
blocking_clarification_height=$(sips -g pixelHeight \
    "$output_dir/blocking-clarification.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$blocking_clarification_width" = "1206" ] \
    && [ "$blocking_clarification_height" = "2478" ] || {
        echo "blocking-clarification capture was ${blocking_clarification_width}x${blocking_clarification_height}" >&2
        exit 65
    }
rg -F "Text = '[Blocking request fixture]'" \
    "$output_dir/blocking-clarification-semantics.txt" >/dev/null
rg -F "Text = '[Hermes needs your input]'" \
    "$output_dir/blocking-clarification-semantics.txt" >/dev/null
rg -F "Text = '[Which environment?]'" \
    "$output_dir/blocking-clarification-semantics.txt" >/dev/null
rg -F "Text = '[Staging]'" \
    "$output_dir/blocking-clarification-semantics.txt" >/dev/null
rg -F "Text = '[Production]'" \
    "$output_dir/blocking-clarification-semantics.txt" >/dev/null
rg -F "Text = '[Continue]'" \
    "$output_dir/blocking-clarification-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.HermesVoiceUiTest#capturesLoadedVoiceSheetOverSettings' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/hermes-voice-settings-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/hermes-voice-settings.png" \
    "$output_dir/hermes-voice-settings.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/hermes-voice-settings-semantics.txt" \
    "$output_dir/hermes-voice-settings-semantics.txt" >/dev/null
hermes_voice_width=$(sips -g pixelWidth \
    "$output_dir/hermes-voice-settings.png" \
    | awk '/pixelWidth/ {print $2}')
hermes_voice_height=$(sips -g pixelHeight \
    "$output_dir/hermes-voice-settings.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$hermes_voice_width" = "1206" ] \
    && [ "$hermes_voice_height" = "2478" ] || {
        echo "Hermes voice capture was ${hermes_voice_width}x${hermes_voice_height}" >&2
        exit 65
    }
rg -F "Text = '[Hermes voice]'" \
    "$output_dir/hermes-voice-settings-semantics.txt" >/dev/null
rg -F "Text = '[Edge TTS]'" \
    "$output_dir/hermes-voice-settings-semantics.txt" >/dev/null
rg -F "Text = '[Current voice · en-US-AriaNeural]'" \
    "$output_dir/hermes-voice-settings-semantics.txt" >/dev/null
rg -F "This changes the global Hermes voice for every app and client using this gateway." \
    "$output_dir/hermes-voice-settings-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.TalkModeUiTest#capturesListeningSurfaceForCrossPlatformParity' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/talk-listening-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/talk-listening.png" \
    "$output_dir/talk-listening.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/talk-listening-semantics.txt" \
    "$output_dir/talk-listening-semantics.txt" >/dev/null
talk_listening_width=$(sips -g pixelWidth \
    "$output_dir/talk-listening.png" \
    | awk '/pixelWidth/ {print $2}')
talk_listening_height=$(sips -g pixelHeight \
    "$output_dir/talk-listening.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$talk_listening_width" = "1206" ] \
    && [ "$talk_listening_height" = "2478" ] || {
        echo "Talk listening capture was ${talk_listening_width}x${talk_listening_height}" >&2
        exit 65
    }
rg -F "Text = '[Talk with Hermes]'" \
    "$output_dir/talk-listening-semantics.txt" >/dev/null
rg -F "Text = '[Brand polish]'" \
    "$output_dir/talk-listening-semantics.txt" >/dev/null
rg -F "Text = '[Listening…]'" \
    "$output_dir/talk-listening-semantics.txt" >/dev/null
rg -F "Speak naturally. Hermes will respond when you pause." \
    "$output_dir/talk-listening-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.SessionShellUiTest#capturesDeterministicBrandScreens' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/brand-shell-instrumentation.txt"
for checkpoint in brand-chat brand-sessions; do
    "$adb_bin" -s "$serial" pull \
        "$checkpoint_dir/${checkpoint}.png" \
        "$output_dir/${checkpoint}.png" >/dev/null
    "$adb_bin" -s "$serial" pull \
        "$checkpoint_dir/${checkpoint}-semantics.txt" \
        "$output_dir/${checkpoint}-semantics.txt" >/dev/null
    checkpoint_width=$(sips -g pixelWidth \
        "$output_dir/${checkpoint}.png" \
        | awk '/pixelWidth/ {print $2}')
    checkpoint_height=$(sips -g pixelHeight \
        "$output_dir/${checkpoint}.png" \
        | awk '/pixelHeight/ {print $2}')
    [ "$checkpoint_width" = "1206" ] \
        && [ "$checkpoint_height" = "2478" ] || {
            echo "$checkpoint capture was ${checkpoint_width}x${checkpoint_height}" >&2
            exit 65
        }
done
rg -F "Text = '[Shaping the mobile agent experience]'" \
    "$output_dir/brand-chat-semantics.txt" >/dev/null
rg -F "Text = '[Sessions · 1 needs input]'" \
    "$output_dir/brand-sessions-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.ModelPickerUiTest#capturesModelPickerOverTheProductionSessionShell' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/model-picker-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/model-picker-app-popup.png" \
    "$output_dir/model-picker-app-popup.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/model-picker-app-popup-semantics.txt" \
    "$output_dir/model-picker-app-popup-semantics.txt" >/dev/null
model_picker_width=$(sips -g pixelWidth \
    "$output_dir/model-picker-app-popup.png" \
    | awk '/pixelWidth/ {print $2}')
model_picker_height=$(sips -g pixelHeight \
    "$output_dir/model-picker-app-popup.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$model_picker_width" = "1206" ] \
    && [ "$model_picker_height" = "2478" ] || {
        echo "model-picker capture was ${model_picker_width}x${model_picker_height}" >&2
        exit 65
    }
rg -F "Tag: 'niles.model_picker.surface'" \
    "$output_dir/model-picker-app-popup-semantics.txt" >/dev/null
rg -F "Text = '[Session model settings]'" \
    "$output_dir/model-picker-app-popup-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.ComposerBlockingPromptUiTest#capturesContextBreakdownOverProductionSessionShell' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/context-breakdown-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/context-breakdown-sheet.png" \
    "$output_dir/context-breakdown-sheet.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/context-breakdown-sheet-semantics.txt" \
    "$output_dir/context-breakdown-sheet-semantics.txt" >/dev/null
context_sheet_width=$(sips -g pixelWidth \
    "$output_dir/context-breakdown-sheet.png" \
    | awk '/pixelWidth/ {print $2}')
context_sheet_height=$(sips -g pixelHeight \
    "$output_dir/context-breakdown-sheet.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$context_sheet_width" = "1206" ] \
    && [ "$context_sheet_height" = "2478" ] || {
        echo "context-sheet capture was ${context_sheet_width}x${context_sheet_height}" >&2
        exit 65
    }
rg -F "Text = '[124.0k of 200.0k · 62%]'" \
    "$output_dir/context-breakdown-sheet-semantics.txt" >/dev/null
rg -F "Text = '[Conversation]'" \
    "$output_dir/context-breakdown-sheet-semantics.txt" >/dev/null
rg -F "Text = '[free]'" \
    "$output_dir/context-breakdown-sheet-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.ComposerBlockingPromptUiTest#capturesGatewayStatsOverProductionSessionShell' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/gateway-stats-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/gateway-stats-sheet.png" \
    "$output_dir/gateway-stats-sheet.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/gateway-stats-sheet-semantics.txt" \
    "$output_dir/gateway-stats-sheet-semantics.txt" >/dev/null
stats_sheet_width=$(sips -g pixelWidth \
    "$output_dir/gateway-stats-sheet.png" \
    | awk '/pixelWidth/ {print $2}')
stats_sheet_height=$(sips -g pixelHeight \
    "$output_dir/gateway-stats-sheet.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$stats_sheet_width" = "1206" ] \
    && [ "$stats_sheet_height" = "2478" ] || {
        echo "stats-sheet capture was ${stats_sheet_width}x${stats_sheet_height}" >&2
        exit 65
    }
rg -F "Text = '[Activity & usage]'" \
    "$output_dir/gateway-stats-sheet-semantics.txt" >/dev/null
rg -F "Text = '[Recorded tokens]'" \
    "$output_dir/gateway-stats-sheet-semantics.txt" >/dev/null
rg -F "Text = '[356.3k]'" \
    "$output_dir/gateway-stats-sheet-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.ComposerBlockingPromptUiTest#capturesRenameDialogOverProductionSessionShell' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/rename-session-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/rename-session-dialog.png" \
    "$output_dir/rename-session-dialog.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/rename-session-dialog-semantics.txt" \
    "$output_dir/rename-session-dialog-semantics.txt" >/dev/null
rename_dialog_width=$(sips -g pixelWidth \
    "$output_dir/rename-session-dialog.png" \
    | awk '/pixelWidth/ {print $2}')
rename_dialog_height=$(sips -g pixelHeight \
    "$output_dir/rename-session-dialog.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$rename_dialog_width" = "1206" ] \
    && [ "$rename_dialog_height" = "2478" ] || {
        echo "rename-dialog capture was ${rename_dialog_width}x${rename_dialog_height}" >&2
        exit 65
    }
rg -F "Tag: 'niles.session.rename.title'" \
    "$output_dir/rename-session-dialog-semantics.txt" >/dev/null
rg -F "Tag: 'niles.session.rename.cancel'" \
    "$output_dir/rename-session-dialog-semantics.txt" >/dev/null
rg -F "Tag: 'niles.session.rename.save'" \
    "$output_dir/rename-session-dialog-semantics.txt" >/dev/null
rg -F "Text = '[Only the currently open Hermes session can be renamed.]'" \
    "$output_dir/rename-session-dialog-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.GoalUiTest#goalButtonOffersOneTapQuickStartsWithoutUsingComposer' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/goal-quick-start-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/goal-quick-start-sheet.png" \
    "$output_dir/goal-quick-start-sheet.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/goal-quick-start-sheet-semantics.txt" \
    "$output_dir/goal-quick-start-sheet-semantics.txt" >/dev/null
goal_sheet_width=$(sips -g pixelWidth \
    "$output_dir/goal-quick-start-sheet.png" \
    | awk '/pixelWidth/ {print $2}')
goal_sheet_height=$(sips -g pixelHeight \
    "$output_dir/goal-quick-start-sheet.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$goal_sheet_width" = "1206" ] \
    && [ "$goal_sheet_height" = "2478" ] || {
        echo "goal-sheet capture was ${goal_sheet_width}x${goal_sheet_height}" >&2
        exit 65
    }
rg -F "Tag: 'niles.goal.sheet'" \
    "$output_dir/goal-quick-start-sheet-semantics.txt" >/dev/null
rg -F "Text = '[Set a standing goal]'" \
    "$output_dir/goal-quick-start-sheet-semantics.txt" >/dev/null
rg -F "Text = '[10 turns]'" \
    "$output_dir/goal-quick-start-sheet-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.GoalUiTest#capturesActiveGoalOnProductionSessionShell' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/goal-active-instrumentation.txt"
for checkpoint in goal-active-card goal-active-details-sheet; do
    "$adb_bin" -s "$serial" pull \
        "$checkpoint_dir/${checkpoint}.png" \
        "$output_dir/${checkpoint}.png" >/dev/null
    "$adb_bin" -s "$serial" pull \
        "$checkpoint_dir/${checkpoint}-semantics.txt" \
        "$output_dir/${checkpoint}-semantics.txt" >/dev/null
    checkpoint_width=$(sips -g pixelWidth \
        "$output_dir/${checkpoint}.png" \
        | awk '/pixelWidth/ {print $2}')
    checkpoint_height=$(sips -g pixelHeight \
        "$output_dir/${checkpoint}.png" \
        | awk '/pixelHeight/ {print $2}')
    [ "$checkpoint_width" = "1206" ] \
        && [ "$checkpoint_height" = "2478" ] || {
            echo "$checkpoint capture was ${checkpoint_width}x${checkpoint_height}" >&2
            exit 65
        }
done
rg -F "Tag: 'niles.goal.card'" \
    "$output_dir/goal-active-card-semantics.txt" >/dev/null
rg -F "Text = '[Active  ·  7/20 turns]'" \
    "$output_dir/goal-active-card-semantics.txt" >/dev/null
rg -F "Tag: 'niles.goal.sheet'" \
    "$output_dir/goal-active-details-sheet-semantics.txt" >/dev/null
rg -F "Text = '[Standing goal]'" \
    "$output_dir/goal-active-details-sheet-semantics.txt" >/dev/null
rg -F "Text = '[More work remains]'" \
    "$output_dir/goal-active-details-sheet-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.TranscriptRowsUiTest#capturesLongHistorySyntaxTailOnProductionSessionShell' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/transcript-syntax-tail-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/transcript-syntax-tail-paired.png" \
    "$output_dir/transcript-syntax-tail-paired.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/transcript-syntax-tail-paired-semantics.txt" \
    "$output_dir/transcript-syntax-tail-paired-semantics.txt" >/dev/null
transcript_syntax_width=$(sips -g pixelWidth \
    "$output_dir/transcript-syntax-tail-paired.png" \
    | awk '/pixelWidth/ {print $2}')
transcript_syntax_height=$(sips -g pixelHeight \
    "$output_dir/transcript-syntax-tail-paired.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$transcript_syntax_width" = "1206" ] \
    && [ "$transcript_syntax_height" = "2478" ] || {
        echo "transcript-syntax capture was ${transcript_syntax_width}x${transcript_syntax_height}" >&2
        exit 65
    }
rg -F "Text = '[History message 40]'" \
    "$output_dir/transcript-syntax-tail-paired-semantics.txt" >/dev/null
rg -F "Text = '[Syntax reference:]'" \
    "$output_dir/transcript-syntax-tail-paired-semantics.txt" >/dev/null
rg -F 'val name = "hermes" // agent' \
    "$output_dir/transcript-syntax-tail-paired-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.TranscriptRowsUiTest#capturesPendingAttachmentsOnProductionSessionShell' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/attachment-composer-and-media-cards-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/attachment-composer-and-media-cards-paired.png" \
    "$output_dir/attachment-composer-and-media-cards-paired.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/attachment-composer-and-media-cards-paired-semantics.txt" \
    "$output_dir/attachment-composer-and-media-cards-paired-semantics.txt" >/dev/null
attachment_capture_width=$(sips -g pixelWidth \
    "$output_dir/attachment-composer-and-media-cards-paired.png" \
    | awk '/pixelWidth/ {print $2}')
attachment_capture_height=$(sips -g pixelHeight \
    "$output_dir/attachment-composer-and-media-cards-paired.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$attachment_capture_width" = "1206" ] \
    && [ "$attachment_capture_height" = "2478" ] || {
        echo "attachment capture was ${attachment_capture_width}x${attachment_capture_height}" >&2
        exit 65
    }
rg -F "Text = '[Compare these two references.]'" \
    "$output_dir/attachment-composer-and-media-cards-paired-semantics.txt" >/dev/null
rg -F "Text = '[reference notes.txt]'" \
    "$output_dir/attachment-composer-and-media-cards-paired-semantics.txt" >/dev/null
rg -F "ContentDescription = '[workspace.jpg]'" \
    "$output_dir/attachment-composer-and-media-cards-paired-semantics.txt" >/dev/null
rg -F "ContentDescription = '[Remove reference.jpg]'" \
    "$output_dir/attachment-composer-and-media-cards-paired-semantics.txt" >/dev/null

"$adb_bin" -s "$serial" shell am instrument -w -r \
    -e class \
    'com.niles.app.DelegationUiTest#mixedDelegationKeepsRowsStableAndExposesExpansionAndChildControls' \
    com.niles.test/androidx.test.runner.AndroidJUnitRunner \
    >"$output_dir/delegation-mixed-instrumentation.txt"
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/delegation-mixed.png" \
    "$output_dir/delegation-mixed.png" >/dev/null
"$adb_bin" -s "$serial" pull \
    "$checkpoint_dir/delegation-mixed-semantics.txt" \
    "$output_dir/delegation-mixed-semantics.txt" >/dev/null
delegation_width=$(sips -g pixelWidth \
    "$output_dir/delegation-mixed.png" \
    | awk '/pixelWidth/ {print $2}')
delegation_height=$(sips -g pixelHeight \
    "$output_dir/delegation-mixed.png" \
    | awk '/pixelHeight/ {print $2}')
[ "$delegation_width" = "1206" ] \
    && [ "$delegation_height" = "2478" ] || {
        echo "delegation capture was ${delegation_width}x${delegation_height}" >&2
        exit 65
    }
rg -F "Tag: 'niles.delegation.overview'" \
    "$output_dir/delegation-mixed-semantics.txt" >/dev/null
rg -F "Text = '[1 working · 1 failed · 1 finished]'" \
    "$output_dir/delegation-mixed-semantics.txt" >/dev/null
rg -F "Text = '[Build delegation UI]'" \
    "$output_dir/delegation-mixed-semantics.txt" >/dev/null

{
    echo "android_commit=$android_commit"
    echo "android_tree=$android_tree"
    echo "pinned_apk_sha256=$actual_apk_sha"
    echo "isolated_app_apk_sha256=$lab_apk_sha"
    echo "instrumentation_apk_sha256=$test_apk_sha"
    echo "system_image=$system_image"
    echo "serial=$serial"
    echo "viewport_pixels=1206x2478"
    echo "density_dpi=480"
    echo "app_content_chrome_top_pixels=72"
    echo "app_content_chrome_bottom_pixels=72"
    shasum -a 256 "$output_dir/onboarding-clean.png"
    shasum -a 256 "$output_dir/onboarding-form.png"
    shasum -a 256 "$output_dir/gateway-removal-dialog.png"
    shasum -a 256 "$output_dir/gateway-removal-dialog-semantics.txt"
    shasum -a 256 "$output_dir/gateway-switch-dialog.png"
    shasum -a 256 "$output_dir/gateway-switch-dialog-semantics.txt"
    shasum -a 256 "$output_dir/brand-chat.png"
    shasum -a 256 "$output_dir/brand-chat-semantics.txt"
    shasum -a 256 "$output_dir/brand-sessions.png"
    shasum -a 256 "$output_dir/brand-sessions-semantics.txt"
    shasum -a 256 "$output_dir/model-picker-app-popup.png"
    shasum -a 256 "$output_dir/model-picker-app-popup-semantics.txt"
    shasum -a 256 "$output_dir/context-breakdown-sheet.png"
    shasum -a 256 "$output_dir/context-breakdown-sheet-semantics.txt"
    shasum -a 256 "$output_dir/gateway-stats-sheet.png"
    shasum -a 256 "$output_dir/gateway-stats-sheet-semantics.txt"
    shasum -a 256 "$output_dir/rename-session-dialog.png"
    shasum -a 256 "$output_dir/rename-session-dialog-semantics.txt"
    shasum -a 256 "$output_dir/goal-quick-start-sheet.png"
    shasum -a 256 "$output_dir/goal-quick-start-sheet-semantics.txt"
    shasum -a 256 "$output_dir/goal-active-card.png"
    shasum -a 256 "$output_dir/goal-active-card-semantics.txt"
    shasum -a 256 "$output_dir/goal-active-details-sheet.png"
    shasum -a 256 "$output_dir/goal-active-details-sheet-semantics.txt"
    shasum -a 256 "$output_dir/transcript-syntax-tail-paired.png"
    shasum -a 256 "$output_dir/transcript-syntax-tail-paired-semantics.txt"
    shasum -a 256 "$output_dir/attachment-composer-and-media-cards-paired.png"
    shasum -a 256 "$output_dir/attachment-composer-and-media-cards-paired-semantics.txt"
    shasum -a 256 "$output_dir/delegation-mixed.png"
    shasum -a 256 "$output_dir/delegation-mixed-semantics.txt"
} >"$output_dir/source.txt"

echo "Android visual references captured at $output_dir"
