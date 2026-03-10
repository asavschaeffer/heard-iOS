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
Usage: scripts/test-ios.sh <command> [count]

Commands:
  voicecore          Run VoiceCore module tests only
  app-build          Run heard build-for-testing only
  app-smoke          Run stable heard smoke tests only
  app-ui             Run stable heard UI tests only
  app-ui-gestures    Run opt-in gesture-based heard UI tests
  app-ui-gestures-repeat [count]
                    Repeat the gesture UI suite (default: 10)
  stable             Run the default stable gate
  experimental       Run experimental VoiceCore perf plus heard experimental tests
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
        -only-testing:VoiceCoreTests \
        -skip-testing:VoiceCoreTests/VoiceCorePerformanceTests
}

run_voicecore_performance_tests() {
    local destination="$1"
    run_xcodebuild "$destination" \
        -scheme VoiceCore \
        test \
        -only-testing:VoiceCoreTests/VoiceCorePerformanceTests
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

latest_xcresult_path() {
    local previous_result="${1:-}"
    local test_log_dir="$DERIVED_DATA_PATH/Logs/Test"
    local latest_result=""
    local fallback_result=""

    while IFS= read -r candidate; do
        if [ -f "$candidate/Info.plist" ]; then
            fallback_result="$candidate"
            if [ -z "$previous_result" ] || [ "$candidate" != "$previous_result" ]; then
                latest_result="$candidate"
            fi
        fi
    done < <(find "$test_log_dir" -maxdepth 1 -name 'Test-*.xcresult' -print | sort)

    if [ -n "$latest_result" ]; then
        echo "$latest_result"
        return
    fi

    if [ -n "$fallback_result" ]; then
        echo "$fallback_result"
        return
    fi

    echo "No xcresult bundles found under $test_log_dir" >&2
    exit 1
}

validate_repeat_count() {
    local repeat_count="$1"

    if [[ ! "$repeat_count" =~ ^[1-9][0-9]*$ ]]; then
        echo "Repeat count must be a positive integer." >&2
        exit 1
    fi
}

run_app_ui_gesture_repeat() {
    local destination="$1"
    local repeat_count="$2"
    local previous_result=""
    local pass_count=0
    local fail_count=0
    local repeat_index
    local -a failure_reports=()

    validate_repeat_count "$repeat_count"

    printf 'Running gesture UI suite %d time(s)\n' "$repeat_count"

    for ((repeat_index = 1; repeat_index <= repeat_count; repeat_index++)); do
        printf '\n[%d/%d] Starting app-ui-gestures\n' "$repeat_index" "$repeat_count"

        local exit_code=0
        if run_app_ui_gesture_tests "$destination"; then
            :
        else
            exit_code=$?
        fi

        local result_path
        result_path="$(latest_xcresult_path "$previous_result")"
        previous_result="$result_path"

        local summary_json
        summary_json="$("$ROOT_DIR/scripts/xcresult-summary.sh" --path "$result_path" --json)"

        local action_json
        action_json="$(jq '.actions[0]' <<<"$summary_json")"

        local status
        local failed_tests
        local skipped_count
        local failed_count
        local attachments
        status="$(jq -r '.status // "unknown"' <<<"$action_json")"
        failed_count="$(jq -r '.failedCount // 0' <<<"$action_json")"
        skipped_count="$(jq -r '.skippedCount // 0' <<<"$action_json")"
        failed_tests="$(jq -r '.failedTests[]?.identifier' <<<"$action_json")"
        attachments="$(jq -r '.attachmentReferences[]?.filename' <<<"$action_json")"

        printf '[%d/%d] status=%s exit=%d failed=%s skipped=%s bundle=%s\n' \
            "$repeat_index" \
            "$repeat_count" \
            "$status" \
            "$exit_code" \
            "$failed_count" \
            "$skipped_count" \
            "$result_path"

        if [ "$exit_code" -eq 0 ]; then
            pass_count=$((pass_count + 1))
            continue
        fi

        fail_count=$((fail_count + 1))

        local failure_report
        failure_report="run $repeat_index: status=$status exit=$exit_code bundle=$result_path"
        if [ -n "$failed_tests" ]; then
            failure_report="$failure_report"$'\n'"failed tests:"
            while IFS= read -r failed_test; do
                [ -n "$failed_test" ] || continue
                failure_report="$failure_report"$'\n'"- $failed_test"
            done <<<"$failed_tests"
        fi
        if [ "$skipped_count" -gt 0 ]; then
            failure_report="$failure_report"$'\n'"skipped: $skipped_count"
        fi
        if [ -n "$attachments" ]; then
            failure_report="$failure_report"$'\n'"attachments:"
            while IFS= read -r attachment; do
                [ -n "$attachment" ] || continue
                failure_report="$failure_report"$'\n'"- $attachment"
            done <<<"$attachments"
        fi

        failure_reports+=("$failure_report")
    done

    printf '\nGesture repeat summary\n'
    printf 'runs: %d | passed: %d | failed: %d\n' "$repeat_count" "$pass_count" "$fail_count"

    if [ "$fail_count" -gt 0 ]; then
        printf '\nFailure details\n'
        printf '%s\n\n' "${failure_reports[@]}"
        return 1
    fi
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
    run_voicecore_performance_tests "$destination"
    restart_simulator "$destination"
    HEARD_ENABLE_GESTURE_UI_TESTS="${HEARD_ENABLE_GESTURE_UI_TESTS:-1}" run_heard_tests "$destination" "$HEARD_EXPERIMENTAL_PLAN"
}

main() {
    if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
        usage
        exit 1
    fi

    ensure_secrets_xcconfig

    local command="$1"
    local repeat_count="${2:-10}"

    if [ "$command" != "app-ui-gestures-repeat" ] && [ "$#" -ne 1 ]; then
        usage
        exit 1
    fi

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
        app-ui-gestures-repeat)
            run_app_ui_gesture_repeat "$destination" "$repeat_count"
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
