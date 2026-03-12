#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/app/HeardChef.xcodeproj"
SECRETS_PATH="$ROOT_DIR/app/Secrets.xcconfig"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.deriveddata/codex-tests}"
TEST_LOG_DIR="$DERIVED_DATA_PATH/Logs/Test"
TEST_RUNS_DIR="$DERIVED_DATA_PATH/Logs/TestRuns"
HEARD_STABLE_PLAN="heard-stable"
HEARD_EXPERIMENTAL_PLAN="heard-experimental"

SCRIPT_CREATED_SECRETS=0
RUN_COMMAND=""
RUN_STATUS="succeeded"
RUN_STARTED_AT=""
RUN_ID=""
RUN_DIR=""
RUN_MANIFEST_PATH=""
RUN_STEPS_FILE=""

usage() {
    cat <<'EOF'
Usage: scripts/test-ios.sh <command> [count]

Commands:
  voicecore          Run VoiceCore module tests only
  app-build          Run heard build-for-testing only
  app-smoke          Run the stable heard hosted test lane
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

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

write_run_manifest() {
    [ -n "$RUN_MANIFEST_PATH" ] || return

    local ended_at="${1:-}"
    local steps_json
    steps_json="$(jq -s '.' "$RUN_STEPS_FILE")"

    jq -n \
        --arg id "$RUN_ID" \
        --arg command "$RUN_COMMAND" \
        --arg startedAt "$RUN_STARTED_AT" \
        --arg endedAt "$ended_at" \
        --arg status "$RUN_STATUS" \
        --argjson steps "$steps_json" \
        '{
            id: $id,
            command: $command,
            startedAt: $startedAt,
            endedAt: $endedAt,
            status: $status,
            steps: $steps
        }' >"$RUN_MANIFEST_PATH"
}

initialize_run_manifest() {
    local command="$1"
    local run_timestamp

    run_timestamp="$(date '+%Y.%m.%d_%H-%M-%S')"
    RUN_COMMAND="$command"
    RUN_STATUS="succeeded"
    RUN_STARTED_AT="$(timestamp)"
    RUN_ID="${run_timestamp}--${command}"
    RUN_DIR="$TEST_RUNS_DIR/$RUN_ID"
    RUN_MANIFEST_PATH="$RUN_DIR/manifest.json"
    RUN_STEPS_FILE="$RUN_DIR/steps.jsonl"

    mkdir -p "$RUN_DIR"
    : >"$RUN_STEPS_FILE"
    write_run_manifest
}

append_run_step() {
    local step_name="$1"
    local step_status="$2"
    local bundle_path="${3:-}"

    if [ "$step_status" != "succeeded" ]; then
        RUN_STATUS="failed"
    fi

    jq -n \
        --arg name "$step_name" \
        --arg status "$step_status" \
        --arg bundlePath "$bundle_path" \
        '{
            name: $name,
            status: $status,
            bundlePath: (
                if $bundlePath == "" then
                    null
                else
                    $bundlePath
                end
            )
        }' >>"$RUN_STEPS_FILE"

    write_run_manifest
}

finalize_run_manifest() {
    local exit_code="$1"

    [ -n "$RUN_MANIFEST_PATH" ] || return
    if [ "$exit_code" -ne 0 ]; then
        RUN_STATUS="failed"
    fi

    write_run_manifest "$(timestamp)"
}

cleanup() {
    local exit_code=$?

    finalize_run_manifest "$exit_code"

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

    local devices_json
    devices_json="$(xcrun simctl list devices available --json)"

    local simulator_id
    simulator_id="$(
        jq -r '
            def runtime_version:
                capture("iOS-(?<versions>[0-9-]+)$").versions
                | split("-")
                | map(tonumber);

            [
                .devices
                | to_entries[]
                | select(.key | contains("iOS"))
                | .key as $runtime
                | .value[]
                | select(.isAvailable == true)
                | {
                    runtime: $runtime,
                    version: ($runtime | runtime_version),
                    name: .name,
                    udid: .udid
                }
            ] as $devices
            | (
                $devices
                | map(select(.name == "iPhone 17 Pro" and .version == [26, 2]))
                | if length > 0 then .[0].udid else empty end
            )
            // (
                $devices
                | map(select(.name == "iPhone 17 Pro"))
                | sort_by(.version)
                | if length > 0 then .[-1].udid else empty end
            )
            // (
                $devices
                | map(select(.name | startswith("iPhone")))
                | sort_by(.version, .name)
                | if length > 0 then .[-1].udid else empty end
            )
            // empty
        ' <<<"$devices_json"
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
        ${RESULT_BUNDLE_PATH:+-resultBundlePath "$RESULT_BUNDLE_PATH"} \
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

run_stable_lane_tests() {
    local destination="$1"
    restart_simulator "$destination"
    run_heard_tests "$destination" "$HEARD_STABLE_PLAN"
}

run_experimental_lane_tests() {
    local destination="$1"
    restart_simulator "$destination"
    HEARD_ENABLE_GESTURE_UI_TESTS="${HEARD_ENABLE_GESTURE_UI_TESTS:-1}" run_heard_tests "$destination" "$HEARD_EXPERIMENTAL_PLAN"
}

current_latest_xcresult_path() {
    local latest_result=""
    local latest_mtime=0

    if [ ! -d "$TEST_LOG_DIR" ]; then
        echo ""
        return
    fi

    while IFS= read -r candidate; do
        [ -f "$candidate/Info.plist" ] || continue

        local candidate_mtime
        candidate_mtime="$(stat -f '%m' "$candidate")"

        if [ -z "$latest_result" ] || [ "$candidate_mtime" -gt "$latest_mtime" ]; then
            latest_result="$candidate"
            latest_mtime="$candidate_mtime"
        fi
    done < <(find "$TEST_LOG_DIR" -maxdepth 1 -name 'Test-*.xcresult' -print)

    echo "$latest_result"
}

latest_xcresult_path() {
    local latest_result

    latest_result="$(current_latest_xcresult_path)"
    if [ -n "$latest_result" ]; then
        echo "$latest_result"
        return
    fi

    echo "No xcresult bundles found under $TEST_LOG_DIR" >&2
    exit 1
}

new_xcresult_path_since() {
    local previous_result="${1:-}"
    local latest_result

    latest_result="$(current_latest_xcresult_path)"

    if [ -z "$latest_result" ]; then
        echo ""
        return
    fi

    if [ -n "$previous_result" ] && [ "$latest_result" = "$previous_result" ]; then
        echo ""
        return
    fi

    echo "$latest_result"
}

sanitize_step_name() {
    local step_name="$1"

    printf '%s' "$step_name" | tr -cs 'A-Za-z0-9._-' '-'
}

result_bundle_path_for_step() {
    local step_name="$1"
    local safe_step_name

    safe_step_name="$(sanitize_step_name "$step_name")"
    printf '%s/Test-%s--%s.xcresult' "$TEST_LOG_DIR" "$safe_step_name" "$RUN_ID"
}

run_logged_step() {
    local step_name="$1"
    local produces_bundle="$2"
    shift 2

    local step_status="succeeded"
    local bundle_path=""
    local exit_code=0

    if [ "$produces_bundle" = "1" ]; then
        mkdir -p "$TEST_LOG_DIR"
        bundle_path="$(result_bundle_path_for_step "$step_name")"
        rm -rf "$bundle_path"
    fi

    if RESULT_BUNDLE_PATH="$bundle_path" "$@"; then
        :
    else
        exit_code=$?
        step_status="failed"
    fi

    if [ "$produces_bundle" = "1" ] && [ ! -d "$bundle_path" ]; then
        bundle_path=""
    fi

    append_run_step "$step_name" "$step_status" "$bundle_path"
    return "$exit_code"
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
    local pass_count=0
    local fail_count=0
    local repeat_index
    local -a failure_reports=()

    validate_repeat_count "$repeat_count"

    printf 'Running gesture UI suite %d time(s)\n' "$repeat_count"

    for ((repeat_index = 1; repeat_index <= repeat_count; repeat_index++)); do
        printf '\n[%d/%d] Starting app-ui-gestures\n' "$repeat_index" "$repeat_count"

        local result_path
        local exit_code=0
        local step_status="succeeded"
        result_path="$(result_bundle_path_for_step "app-ui-gestures-$repeat_index")"
        mkdir -p "$TEST_LOG_DIR"
        rm -rf "$result_path"

        if RESULT_BUNDLE_PATH="$result_path" run_app_ui_gesture_tests "$destination"; then
            :
        else
            exit_code=$?
            step_status="failed"
        fi

        if [ ! -d "$result_path" ]; then
            result_path=""
        fi
        append_run_step "app-ui-gestures-$repeat_index" "$step_status" "$result_path"

        local status="$step_status"
        local failed_tests=""
        local skipped_count="0"
        local failed_count="0"
        local attachments=""

        if [ -n "$result_path" ]; then
            local summary_json
            local action_json

            summary_json="$("$ROOT_DIR/scripts/xcresult-summary.sh" --path "$result_path" --json)"
            action_json="$(jq '.actions[0]' <<<"$summary_json")"
            status="$(jq -r '.status // "unknown"' <<<"$action_json")"
            failed_count="$(jq -r '.failedCount // 0' <<<"$action_json")"
            skipped_count="$(jq -r '.skippedCount // 0' <<<"$action_json")"
            failed_tests="$(jq -r '.failedTests[]?.identifier' <<<"$action_json")"
            attachments="$(jq -r '.attachmentReferences[]?.filename' <<<"$action_json")"
        fi

        printf '[%d/%d] status=%s exit=%d failed=%s skipped=%s bundle=%s\n' \
            "$repeat_index" \
            "$repeat_count" \
            "$status" \
            "$exit_code" \
            "$failed_count" \
            "$skipped_count" \
            "${result_path:-none}"

        if [ "$exit_code" -eq 0 ]; then
            pass_count=$((pass_count + 1))
            continue
        fi

        fail_count=$((fail_count + 1))

        local failure_report
        failure_report="run $repeat_index: status=$status exit=$exit_code bundle=${result_path:-none}"
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

    run_logged_step "voicecore" 1 run_voicecore_tests "$destination"
    run_logged_step "app-build" 0 run_app_build_for_testing "$destination"
    run_logged_step "heard-stable" 1 run_stable_lane_tests "$destination"
}

run_experimental_gate() {
    local destination="$1"

    run_logged_step "voicecore-performance" 1 run_voicecore_performance_tests "$destination"
    run_logged_step "heard-experimental" 1 run_experimental_lane_tests "$destination"
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

    initialize_run_manifest "$command"

    local destination
    destination="$(resolve_destination)"
    printf 'Using simulator destination: %s\n' "$destination"
    boot_simulator_if_needed "$destination"

    case "$command" in
        voicecore)
            run_logged_step "voicecore" 1 run_voicecore_tests "$destination"
            ;;
        app-build)
            run_logged_step "app-build" 0 run_app_build_for_testing "$destination"
            ;;
        app-smoke)
            run_logged_step "app-smoke" 1 run_app_smoke_tests "$destination"
            ;;
        app-ui)
            run_logged_step "app-ui" 1 run_app_ui_tests "$destination"
            ;;
        app-ui-gestures)
            run_logged_step "app-ui-gestures" 1 run_app_ui_gesture_tests "$destination"
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
