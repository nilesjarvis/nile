#!/bin/bash
set -Euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCOPE="${1:-full}"
PINNED_ANDROID_REF="bd5451da891f2d886b9bc35f8ea67d6920df1d98"
PINNED_HERMES_REF="7441e3395f9db0d8319f43bfe07dfb222777101e"
CANONICAL_SIMULATOR_NAME="${NILE_LAB_SIMULATOR_NAME:-iPhone 17 Pro}"
CANONICAL_RUNTIME_VERSION="${NILE_LAB_RUNTIME_VERSION:-26.5}"
FAILURES=0

usage() {
    cat <<'EOF'
Usage: scripts/test-lab/doctor.sh [unit|ui|accessibility|visual|smoke|full|drive|installer]

This command is read-only. It checks only the prerequisites needed by the
selected disposable iOS/Hermes test-lab lane.
EOF
}

pass() {
    printf '[pass] %s\n' "$*"
}

fail() {
    printf '[fail] %s\n' "$*" >&2
    FAILURES=$((FAILURES + 1))
}

require_command() {
    local command_name="$1"
    local command_path
    command_path="$(command -v "$command_name" 2>/dev/null || true)"
    if [[ -n "$command_path" ]]; then
        pass "$command_name: $command_path"
    else
        fail "required command is unavailable: $command_name"
    fi
}

case "$SCOPE" in
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

for command_name in bash git python3 xcodebuild xcrun swift xcodegen plutil; do
    require_command "$command_name"
done

if [[ "$SCOPE" == "visual" || "$SCOPE" == "full" ]]; then
    require_command jq
fi

if [[ "$SCOPE" == "smoke" || "$SCOPE" == "full" || \
    "$SCOPE" == "drive" || "$SCOPE" == "installer" ]]; then
    require_command curl
fi

if xcode_version="$(xcodebuild -version 2>/dev/null)"; then
    pass "${xcode_version//$'\n'/; }"
else
    fail "xcodebuild could not read a complete Xcode installation"
fi

if swift_version="$(swift --version 2>/dev/null | head -n 1)"; then
    pass "$swift_version"
else
    fail "Swift toolchain could not be queried"
fi

if xcodegen_version="$(xcodegen --version 2>/dev/null)"; then
    pass "XcodeGen $xcodegen_version"
else
    fail "XcodeGen could not be queried"
fi

simulator_json="$(xcrun simctl list devices available -j 2>/dev/null || true)"
if [[ -z "$simulator_json" ]]; then
    fail "CoreSimulator did not return any available device inventory"
else
    canonical_udid="$(
        SIMULATOR_JSON="$simulator_json" python3 - \
            "$CANONICAL_SIMULATOR_NAME" "$CANONICAL_RUNTIME_VERSION" <<'PY'
import json
import os
import sys

name, version = sys.argv[1:]
payload = json.loads(os.environ["SIMULATOR_JSON"])
needle = f"SimRuntime.iOS-{version.replace('.', '-')}"
matches = [
    device
    for runtime, devices in payload.get("devices", {}).items()
    if needle in runtime
    for device in devices
    if device.get("isAvailable") and device.get("name") == name
]
print(matches[0]["udid"] if matches else "")
PY
    )"
    if [[ -n "$canonical_udid" ]]; then
        pass "canonical Simulator: $CANONICAL_SIMULATOR_NAME iOS $CANONICAL_RUNTIME_VERSION ($canonical_udid)"
    else
        fail "canonical Simulator is unavailable: $CANONICAL_SIMULATOR_NAME iOS $CANONICAL_RUNTIME_VERSION"
    fi
fi

if [[ -f "$ROOT_DIR/Nile.xcodeproj/project.pbxproj" && \
    -f "$ROOT_DIR/project.yml" ]]; then
    pass "Nile Xcode project and XcodeGen specification are present"
else
    fail "Nile.xcodeproj or project.yml is missing"
fi

if "$ROOT_DIR/scripts/reference/verify-android.sh" >/dev/null 2>&1; then
    pass "Android oracle is clean at $PINNED_ANDROID_REF"
else
    fail "Android oracle verification failed; run scripts/reference/verify-android.sh"
fi

if [[ -s "$ROOT_DIR/scripts/test-lab/hermes.ref" ]]; then
    actual_hermes_ref="$(tr -d '[:space:]' < "$ROOT_DIR/scripts/test-lab/hermes.ref")"
    if [[ "$actual_hermes_ref" == "$PINNED_HERMES_REF" ]]; then
        pass "Hermes compatibility ref: $actual_hermes_ref"
    else
        fail "Hermes ref differs from the Android compatibility pin"
    fi
else
    fail "scripts/test-lab/hermes.ref is missing or empty"
fi

if [[ -d "$ROOT_DIR/.reference/hermes/.git" ]]; then
    local_hermes_ref="$(git -C "$ROOT_DIR/.reference/hermes" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$local_hermes_ref" == "$PINNED_HERMES_REF" ]] && \
        git -C "$ROOT_DIR/.reference/hermes" diff --quiet --ignore-submodules -- && \
        git -C "$ROOT_DIR/.reference/hermes" diff --cached --quiet --ignore-submodules --; then
        pass "optional local Hermes oracle is clean at the exact pin"
    else
        fail "optional .reference/hermes checkout is not clean at the exact pin"
    fi
fi

if [[ "$SCOPE" == "visual" || "$SCOPE" == "full" ]]; then
    if [[ -x "$ROOT_DIR/scripts/visual/compare.sh" && \
        -x "$ROOT_DIR/scripts/visual/test.sh" && \
        -x "$ROOT_DIR/scripts/visual/capture-android.sh" && \
        -f "$ROOT_DIR/scripts/visual/manifests/onboarding.json" && \
        -f "$ROOT_DIR/scripts/visual/manifests/onboarding-form.json" ]]; then
        pass "visual comparer, capture tool, regression suite, and onboarding manifests are present"
    else
        fail "visual comparer inputs are incomplete"
    fi
    android_capture="$ROOT_DIR/scripts/visual/baselines/android/onboarding-clean.png"
    android_form_capture="$ROOT_DIR/scripts/visual/baselines/android/onboarding-form.png"
    if [[ -s "$android_capture" && -s "$android_form_capture" ]]; then
        pass "tracked pinned Android onboarding captures are present"
    else
        fail "missing tracked pinned Android onboarding captures"
    fi
fi

if [[ "$SCOPE" == "smoke" || "$SCOPE" == "full" || \
    "$SCOPE" == "drive" ]]; then
    if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
        fail "do not export OPENROUTER_API_KEY; the runner uses a one-use secure handoff"
    else
        pass "no exported OpenRouter credential is visible"
    fi
    if [[ -n "${NILE_LAB_OPENROUTER_KEY_FILE:-}" ]]; then
        key_file="$NILE_LAB_OPENROUTER_KEY_FILE"
        if [[ -f "$key_file" && ! -L "$key_file" ]]; then
            key_mode="$(stat -f '%Lp' "$key_file" 2>/dev/null || true)"
            if [[ "$key_mode" == "600" ]]; then
                pass "OpenRouter key handoff is a regular owner-only file"
            else
                fail "OpenRouter key handoff must have mode 600"
            fi
        else
            fail "OpenRouter key handoff must be a non-symlink regular file"
        fi
    else
        pass "runner will request the OpenRouter key from the controlling terminal after setup"
    fi
fi

if (( FAILURES > 0 )); then
    printf '\nDoctor found %d prerequisite failure(s).\n' "$FAILURES" >&2
    exit 1
fi

printf '\nDoctor passed for the %s lane without changing the workspace.\n' "$SCOPE"
