#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/app/HeardChef.xcodeproj"
SECRETS_PATH="$ROOT_DIR/app/Secrets.xcconfig"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.deriveddata/codex-tests}"
HEARD_STABLE_PLAN="heard-stable"
HEARD_EXPERIMENTAL_PLAN="heard-experimental"

SCRIPT_CREATED_SECRETS=0

usage() {
    cat <<'EOF'
Usage: scripts/test-ios.sh <command>

Commands:
  voicecore          Run VoiceCore module tests only
  app-build          Run heard build-for-testing only
  app-smoke          Run stable heard smoke tests only
  app-ui             Run stable heard UI tests only
  app-ui-gestures    Run opt-in gesture-based heard UI tests
  stable             Run the default stable gate
  experimental       Run the current experimental heard test plan
  all                Alias for stable

Optional environment:
  UITEST_SCENARIO            Override the scenario used by UI tests
  HEARD_ENABLE_GESTURE_UI_TESTS
  IOS_SIMULATOR_ID            Explicit simulator UUID
  IOS_SIMULATOR_DESTINATION   Full xcodebuild -destination string
  DERIVED_DATA_PATH           Override derived data location
EOF
}

cleanup() {
    if [ "$SCRIPT_CREATED_SECRETS" -eq 1 ] && [ -f "$SECRETS_PATH" ]; then
        rm -f "$SECRETS_PATH"
    fi
}

trap cleanup EXIT

ensure_secrets_xcconfig() {
    if [ -f "$SECRETS_PATH" ]; then
        return
    fi

    cat >"$SECRETS_PATH" <<'EOF'
GEMINI_API_KEY =
EOF

    SCRIPT_CREATED_SECRETS=1
}

resolve_destination() {
    if [ -n "${IOS_SIMULATOR_DESTINATION:-}" ]; then
        echo "$IOS_SIMULATOR_DESTINATION"
        return
    fi

    if [ -n "${IOS_SIMULATOR_ID:-}" ]; then
        echo "platform=iOS Simulator,id=${IOS_SIMULATOR_ID}"
        return
    fi

    local simulator_id
    simulator_id="$(
        xcrun simctl list devices available |
            awk -F '[()]' '/iPhone/ && ($0 ~ /Booted/ || $0 ~ /Shutdown/) { print $2; exit }'
    )"

    if [ -z "$simulator_id" ]; then
        echo "No available iPhone simulator found." >&2
        exit 1
    fi

    echo "platform=iOS Simulator,id=${simulator_id}"
}

extract_simulator_id() {
    local destination="$1"

    if [[ "$destination" != platform=iOS\ Simulator,id=* ]]; then
        return 1
    fi

    echo "${destination##*=}"
}

boot_simulator_if_needed() {
    local destination="$1"
    local simulator_id
    simulator_id="$(extract_simulator_id "$destination")" || return

    xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$simulator_id" -b >/dev/null
}

restart_simulator() {
    local destination="$1"
    local simulator_id
    simulator_id="$(extract_simulator_id "$destination")" || return

    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$simulator_id" -b >/dev/null
}

run_xcodebuild() {
    local destination="$1"
    shift

    xcodebuild \
        -project "$PROJECT_PATH" \
        -destination "$destination" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        "$@"
}

run_heard_tests() {
    local destination="$1"
    local plan="$2"
    shift 2

    run_xcodebuild "$destination" \
        -scheme heard \
        -testPlan "$plan" \
        test \
        "$@"
}

run_voicecore_tests() {
    local destination="$1"
    run_xcodebuild "$destination" \
        -scheme VoiceCore \
        test \
        -only-testing:VoiceCoreTests
}

run_app_build_for_testing() {
    local destination="$1"
    run_xcodebuild "$destination" \
        -scheme heard \
        build-for-testing
}

run_app_smoke_tests() {
    local destination="$1"
    run_heard_tests "$destination" "$HEARD_STABLE_PLAN" \
        -only-testing:heardTests
}

run_app_ui_tests() {
    local destination="$1"
    restart_simulator "$destination"
    run_heard_tests "$destination" "$HEARD_STABLE_PLAN" \
        -only-testing:heardUITests
}

run_app_ui_gesture_tests() {
    local destination="$1"
    restart_simulator "$destination"
    HEARD_ENABLE_GESTURE_UI_TESTS="${HEARD_ENABLE_GESTURE_UI_TESTS:-1}" run_heard_tests "$destination" "$HEARD_EXPERIMENTAL_PLAN" \
        -only-testing:heardUITests/KeyboardDismissUITests
}

run_stable_gate() {
    local destination="$1"

    run_voicecore_tests "$destination"
    run_app_build_for_testing "$destination"
    restart_simulator "$destination"
    run_heard_tests "$destination" "$HEARD_STABLE_PLAN"
}

run_experimental_gate() {
    local destination="$1"
    restart_simulator "$destination"
    HEARD_ENABLE_GESTURE_UI_TESTS="${HEARD_ENABLE_GESTURE_UI_TESTS:-1}" run_heard_tests "$destination" "$HEARD_EXPERIMENTAL_PLAN"
}

main() {
    if [ "$#" -ne 1 ]; then
        usage
        exit 1
    fi

    ensure_secrets_xcconfig

    local command="$1"
    local destination
    destination="$(resolve_destination)"
    boot_simulator_if_needed "$destination"

    case "$command" in
        voicecore)
            run_voicecore_tests "$destination"
            ;;
        app-build)
            run_app_build_for_testing "$destination"
            ;;
        app-smoke)
            run_app_smoke_tests "$destination"
            ;;
        app-ui)
            run_app_ui_tests "$destination"
            ;;
        app-ui-gestures)
            run_app_ui_gesture_tests "$destination"
            ;;
        stable)
            run_stable_gate "$destination"
            ;;
        experimental)
            run_experimental_gate "$destination"
            ;;
        all)
            run_stable_gate "$destination"
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

main "$@"
