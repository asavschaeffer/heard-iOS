#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/.deriveddata/codex-tests}"
TEST_LOG_DIR="$DERIVED_DATA_PATH/Logs/Test"
OUTPUT_MODE="text"
SUMMARY_MODE="single"
RESULT_PATH=""
ALL_RESULTS_DIR="$TEST_LOG_DIR"

usage() {
    cat <<'EOF'
Usage: scripts/xcresult-summary.sh [--json|--markdown] [--latest] [--path <xcresult-path>] [--all [xcresult-dir]] [xcresult-path]

Options:
  --json      Emit machine-readable JSON
  --markdown  Emit GitHub-friendly markdown
  --latest    Use the latest xcresult bundle in derived data
  --path      Use an explicit xcresult bundle path
  --all       Summarize every xcresult bundle in a directory (default: derived data test logs)

If no path is provided, the script defaults to --latest.
EOF
}

resolve_latest_result() {
    local latest_result=""
    while IFS= read -r candidate; do
        if [ -f "$candidate/Info.plist" ]; then
            latest_result="$candidate"
        fi
    done < <(find "$TEST_LOG_DIR" -maxdepth 1 -name 'Test-*.xcresult' -print | sort)

    if [ -z "$latest_result" ]; then
        echo "No xcresult bundles found under $TEST_LOG_DIR" >&2
        exit 1
    fi

    echo "$latest_result"
}

collect_result_paths() {
    local search_dir="$1"

    if [ ! -d "$search_dir" ]; then
        echo "xcresult directory not found: $search_dir" >&2
        exit 1
    fi

    find "$search_dir" -maxdepth 1 -name 'Test-*.xcresult' -print |
        sort |
        while IFS= read -r candidate; do
            [ -f "$candidate/Info.plist" ] || continue
            printf '%s\n' "$candidate"
        done
}

render_all_markdown() {
    local summary_json="$1"

    jq -r '
        [
            "## xcresult Gate Summary",
            "",
            "- Directory: `" + .path + "`",
            "- Bundles: `" + (.aggregate.bundlesCount | tostring) + "`",
            "- Status: `" + .aggregate.status + "`",
            "- Duration: `" + ((.aggregate.duration * 100 | round / 100) | tostring) + "s`",
            "- Counts: `passed " + (.aggregate.passedCount | tostring) + " / failed " + (.aggregate.failedCount | tostring) + " / skipped " + (.aggregate.skippedCount | tostring) + " / total " + (.aggregate.testsCount | tostring) + "`",
            (
                if (.aggregate.failedBundles | length) > 0 then
                    "- Failed bundles:\n" + (.aggregate.failedBundles | map("  - `" + . + "`") | join("\n"))
                else
                    "- Failed bundles: none"
                end
            ),
            "",
            (
                .bundles[]
                | "### Bundle `" + .path + "`",
                  "",
                  (
                      .actions[]
                      | "- " + .title +
                        ": `" + .status + "` " +
                        "(passed " + (.passedCount | tostring) +
                        " / failed " + (.failedCount | tostring) +
                        " / skipped " + (.skippedCount | tostring) +
                        " / total " + (.testsCount | tostring) + ")" +
                        " on `" + .device + "`" +
                        (
                            if (.failedTests | length) > 0 then
                                "\n  - Failed tests:\n" + (.failedTests | map("    - `" + .identifier + "`") | join("\n"))
                            else
                                ""
                            end
                        ) +
                        (
                            if (.failureIssues | length) > 0 then
                                "\n  - Failure issues:\n" + (.failureIssues | map("    - `" + .testCaseName + "`: " + .message) | join("\n"))
                            else
                                ""
                            end
                        )
                  ),
                  ""
            )
        ] | join("\n")
    ' <<<"$summary_json"
}

render_all_text() {
    local summary_json="$1"

    jq -r '
        "xcresult directory: " + .path,
        "gate status: " + .aggregate.status +
        " | bundles: " + (.aggregate.bundlesCount | tostring) +
        " | duration: " + ((.aggregate.duration * 100 | round / 100) | tostring) + "s" +
        " | tests: " + (.aggregate.testsCount | tostring) +
        " | passed: " + (.aggregate.passedCount | tostring) +
        " | failed: " + (.aggregate.failedCount | tostring) +
        " | skipped: " + (.aggregate.skippedCount | tostring),
        (
            if (.aggregate.failedBundles | length) > 0 then
                "failed bundles:\n" + (.aggregate.failedBundles | map("- " + .) | join("\n"))
            else
                empty
            end
        ),
        (
            .bundles[]
            | "\nbundle: " + .path,
              (
                  .actions[]
                  | "- " + .title +
                    " | status: " + .status +
                    " | device: " + .device +
                    " | runtime: " + .runtime +
                    " | duration: " + ((.duration * 100 | round / 100) | tostring) + "s" +
                    " | tests: " + (.testsCount | tostring) +
                    " | passed: " + (.passedCount | tostring) +
                    " | failed: " + (.failedCount | tostring) +
                    " | skipped: " + (.skippedCount | tostring) +
                    (
                        if (.failedTests | length) > 0 then
                            "\n  failed tests:\n" + (.failedTests | map("  - " + .identifier) | join("\n"))
                        else
                            ""
                        end
                    ) +
                    (
                        if (.failureIssues | length) > 0 then
                            "\n  failure issues:\n" + (.failureIssues | map("  - " + .testCaseName + ": " + .message) | join("\n"))
                        else
                            ""
                        end
                    )
              )
        )
    ' <<<"$summary_json"
}

summarize_all_results() {
    local search_dir="$1"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    local bundle_file="$tmp_dir/bundles.jsonl"
    touch "$bundle_file"

    while IFS= read -r bundle_path; do
        "$ROOT_DIR/scripts/xcresult-summary.sh" --path "$bundle_path" --json >>"$bundle_file"
    done < <(collect_result_paths "$search_dir")

    if [ ! -s "$bundle_file" ]; then
        echo "No xcresult bundles found under $search_dir" >&2
        rm -rf "$tmp_dir"
        exit 1
    fi

    local summary_json
    summary_json="$(
        jq -s --arg path "$search_dir" '
            {
                path: $path,
                aggregate: {
                    bundlesCount: length,
                    actionsCount: ([.[].actions | length] | add // 0),
                    status: (
                        if ([.[] | .actions[]? | select(.status != "succeeded")] | length) > 0
                        then "failed"
                        else "succeeded"
                        end
                    ),
                    duration: ([.[].actions[]?.duration] | add // 0),
                    testsCount: ([.[].actions[]?.testsCount] | add // 0),
                    passedCount: ([.[].actions[]?.passedCount] | add // 0),
                    failedCount: ([.[].actions[]?.failedCount] | add // 0),
                    skippedCount: ([.[].actions[]?.skippedCount] | add // 0),
                    bundlePaths: [.[].path],
                    failedBundles: [
                        .[]
                        | select([.actions[]? | select(.status != "succeeded")] | length > 0)
                        | .path
                    ]
                },
                bundles: .
            }
        ' "$bundle_file"
    )"

    rm -rf "$tmp_dir"

    if [ "$OUTPUT_MODE" = "json" ]; then
        printf '%s\n' "$summary_json"
        exit 0
    fi

    if [ "$OUTPUT_MODE" = "markdown" ]; then
        render_all_markdown "$summary_json"
        exit 0
    fi

    render_all_text "$summary_json"
    exit 0
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)
            OUTPUT_MODE="json"
            ;;
        --markdown)
            OUTPUT_MODE="markdown"
            ;;
        --latest)
            SUMMARY_MODE="single"
            RESULT_PATH="$(resolve_latest_result)"
            ;;
        --path)
            shift
            if [ "$#" -eq 0 ]; then
                echo "--path requires an xcresult bundle path." >&2
                exit 1
            fi
            SUMMARY_MODE="single"
            RESULT_PATH="$1"
            ;;
        --all)
            SUMMARY_MODE="all"
            if [ "$#" -gt 1 ] && [[ "$2" != -* ]]; then
                shift
                ALL_RESULTS_DIR="$1"
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [ "$SUMMARY_MODE" = "all" ]; then
                echo "Positional xcresult paths are not supported with --all." >&2
                exit 1
            fi
            if [ -n "$RESULT_PATH" ]; then
                echo "Only one xcresult path may be provided." >&2
                exit 1
            fi
            RESULT_PATH="$1"
            ;;
    esac
    shift
done

if [ "$SUMMARY_MODE" = "all" ]; then
    summarize_all_results "$ALL_RESULTS_DIR"
fi

if [ -z "$RESULT_PATH" ]; then
    RESULT_PATH="$(resolve_latest_result)"
fi

if [ ! -d "$RESULT_PATH" ]; then
    echo "xcresult bundle not found: $RESULT_PATH" >&2
    exit 1
fi

INVOCATION_JSON="$(xcrun xcresulttool get --legacy --path "$RESULT_PATH" --format json)"
ACTION_COUNT="$(jq '.actions._values | length' <<<"$INVOCATION_JSON")"

if [ "$ACTION_COUNT" -eq 0 ]; then
    echo "No actions found in xcresult bundle: $RESULT_PATH" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

ACTION_SUMMARIES_FILE="$TMP_DIR/actions.jsonl"
touch "$ACTION_SUMMARIES_FILE"

for ((i = 0; i < ACTION_COUNT; i++)); do
    TITLE="$(jq -r ".actions._values[$i].title._value // \"Action $((i + 1))\"" <<<"$INVOCATION_JSON")"
    STATUS="$(jq -r ".actions._values[$i].actionResult.status._value // \"unknown\"" <<<"$INVOCATION_JSON")"
    TESTS_COUNT="$(jq -r ".actions._values[$i].actionResult.metrics.testsCount._value // \"0\"" <<<"$INVOCATION_JSON")"
    SKIPPED_COUNT="$(jq -r ".actions._values[$i].actionResult.metrics.testsSkippedCount._value // \"0\"" <<<"$INVOCATION_JSON")"
    DEVICE_NAME="$(jq -r ".actions._values[$i].runDestination.displayName._value // \"unknown\"" <<<"$INVOCATION_JSON")"
    DEVICE_RUNTIME="$(jq -r ".actions._values[$i].runDestination.targetSDKRecord.operatingSystemVersion._value // .actions._values[$i].runDestination.targetDeviceRecord.operatingSystemVersion._value // \"unknown\"" <<<"$INVOCATION_JSON")"
    DEVICE_IDENTIFIER="$(jq -r ".actions._values[$i].runDestination.targetDeviceRecord.identifier._value // \"\"" <<<"$INVOCATION_JSON")"
    SDK_NAME="$(jq -r ".actions._values[$i].runDestination.targetSDKRecord.name._value // \"\"" <<<"$INVOCATION_JSON")"
    STARTED_AT="$(jq -r ".actions._values[$i].startedTime._value // empty" <<<"$INVOCATION_JSON")"
    ENDED_AT="$(jq -r ".actions._values[$i].endedTime._value // empty" <<<"$INVOCATION_JSON")"
    TESTS_REF_ID="$(jq -r ".actions._values[$i].actionResult.testsRef.id._value // empty" <<<"$INVOCATION_JSON")"
    FAILURE_ISSUES_JSON="$(jq -c "
        [
            ((.actions._values[$i].actionResult.issues.testFailureSummaries._values // [])[]? | {
                type: \"testFailure\",
                testCaseName: (.testCaseName._value // \"unknown\"),
                message: (.message._value // \"\"),
                file: (.documentLocationInCreatingWorkspace.url._value // \"\")
            }),
            ((.actions._values[$i].actionResult.issues.buildFailureSummaries._values // [])[]? | {
                type: \"buildFailure\",
                testCaseName: (.issueType._value // \"build\"),
                message: (.message._value // \"\"),
                file: (.documentLocationInCreatingWorkspace.url._value // \"\")
            }),
            ((.actions._values[$i].actionResult.issues.errorSummaries._values // [])[]? | {
                type: \"error\",
                testCaseName: (.issueType._value // \"error\"),
                message: (.message._value // \"\"),
                file: (.documentLocationInCreatingWorkspace.url._value // \"\")
            })
        ]
    " <<<"$INVOCATION_JSON")"

    TEST_ENTRIES_JSON='[]'
    FAILED_TESTS_JSON='[]'
    SKIPPED_TESTS_JSON='[]'
    SUITES_JSON='[]'
    ATTACHMENT_REFERENCES_JSON='[]'
    ACTION_DURATION='0'

    if [ -n "$TESTS_REF_ID" ]; then
        TESTS_JSON="$(xcrun xcresulttool get --legacy --path "$RESULT_PATH" --id "$TESTS_REF_ID" --format json)"
        TEST_ENTRIES_JSON="$(jq -c '
            [
                .. | objects
                | select((._type._name? // "") == "ActionTestMetadata")
                | {
                    identifier: (.identifier._value // .name._value // "unknown"),
                    name: (.name._value // "unknown"),
                    suite: (((.identifier._value // .name._value // "unknown") | split("/"))[0]),
                    status: (.testStatus._value // "Unknown"),
                    duration: (.duration._value | tonumber? // 0),
                    summaryRef: (.summaryRef.id._value // "")
                }
            ]
        ' <<<"$TESTS_JSON")"
        FAILED_TESTS_JSON="$(jq -c '[.[] | select(.status == "Failure")]' <<<"$TEST_ENTRIES_JSON")"
        SKIPPED_TESTS_JSON="$(jq -c '[.[] | select(.status == "Skipped")]' <<<"$TEST_ENTRIES_JSON")"
        SUITES_JSON="$(jq -c '
            sort_by(.suite)
            | group_by(.suite)
            | map({
                name: .[0].suite,
                target: .[0].suite,
                kind: "testSuite",
                duration: (map(.duration) | add // 0),
                testsCount: length,
                failedCount: (map(select(.status == "Failure")) | length),
                skippedCount: (map(select(.status == "Skipped")) | length)
            })
        ' <<<"$TEST_ENTRIES_JSON")"
        ACTION_DURATION="$(jq -r '[.[].duration] | add // 0' <<<"$SUITES_JSON")"

        FAILED_SUMMARY_REFS="$(jq -r '.[] | .summaryRef | select(length > 0)' <<<"$FAILED_TESTS_JSON")"
        if [ -n "$FAILED_SUMMARY_REFS" ]; then
            ATTACHMENTS_FILE="$TMP_DIR/attachments-$i.jsonl"
            touch "$ATTACHMENTS_FILE"
            while IFS= read -r summary_ref; do
                [ -n "$summary_ref" ] || continue
                TEST_SUMMARY_JSON="$(xcrun xcresulttool get --legacy --path "$RESULT_PATH" --id "$summary_ref" --format json)"
                jq -c --arg summaryRef "$summary_ref" '
                    [
                        .. | objects
                        | select(has("attachments"))
                        | .attachments._values[]?
                        | {
                            summaryRef: $summaryRef,
                            name: (.name._value // .filename._value // "attachment"),
                            filename: (.filename._value // ""),
                            uniformTypeIdentifier: (.uniformTypeIdentifier._value // ""),
                            payloadRef: (.payloadRef.id._value // "")
                        }
                    ][]
                ' <<<"$TEST_SUMMARY_JSON" >>"$ATTACHMENTS_FILE"
            done <<<"$FAILED_SUMMARY_REFS"

            if [ -s "$ATTACHMENTS_FILE" ]; then
                ATTACHMENT_REFERENCES_JSON="$(jq -s '.' "$ATTACHMENTS_FILE")"
            fi
        fi
    fi

    FAILED_COUNT="$(jq -r 'length' <<<"$FAILED_TESTS_JSON")"
    PASSED_COUNT="$((TESTS_COUNT - FAILED_COUNT - SKIPPED_COUNT))"
    if [ "$PASSED_COUNT" -lt 0 ]; then
        PASSED_COUNT=0
    fi

    jq -n \
        --arg path "$RESULT_PATH" \
        --arg title "$TITLE" \
        --arg status "$STATUS" \
        --arg device "$DEVICE_NAME" \
        --arg runtime "$DEVICE_RUNTIME" \
        --arg deviceIdentifier "$DEVICE_IDENTIFIER" \
        --arg sdk "$SDK_NAME" \
        --arg startedAt "$STARTED_AT" \
        --arg endedAt "$ENDED_AT" \
        --argjson duration "$ACTION_DURATION" \
        --argjson testsCount "$TESTS_COUNT" \
        --argjson skippedCount "$SKIPPED_COUNT" \
        --argjson failedCount "$FAILED_COUNT" \
        --argjson passedCount "$PASSED_COUNT" \
        --argjson suites "$SUITES_JSON" \
        --argjson failedTests "$FAILED_TESTS_JSON" \
        --argjson skippedTests "$SKIPPED_TESTS_JSON" \
        --argjson failureIssues "$FAILURE_ISSUES_JSON" \
        --argjson perTestDurations "$TEST_ENTRIES_JSON" \
        --argjson attachmentReferences "$ATTACHMENT_REFERENCES_JSON" \
        '{
            path: $path,
            title: $title,
            status: $status,
            device: $device,
            runtime: $runtime,
            deviceIdentifier: $deviceIdentifier,
            sdk: $sdk,
            startedAt: $startedAt,
            endedAt: $endedAt,
            duration: $duration,
            testsCount: $testsCount,
            skippedCount: $skippedCount,
            failedCount: $failedCount,
            passedCount: $passedCount,
            suites: $suites,
            failedTests: $failedTests,
            skippedTests: $skippedTests,
            failureIssues: $failureIssues,
            perTestDurations: $perTestDurations,
            attachmentReferences: $attachmentReferences
        }' >>"$ACTION_SUMMARIES_FILE"
done

SUMMARY_JSON="$(jq -s --arg path "$RESULT_PATH" '{path: $path, actions: .}' "$ACTION_SUMMARIES_FILE")"

if [ "$OUTPUT_MODE" = "json" ]; then
    printf '%s\n' "$SUMMARY_JSON"
    exit 0
fi

if [ "$OUTPUT_MODE" = "markdown" ]; then
    jq -r '
        [
            "## xcresult Summary",
            "",
            "- Bundle: `" + .path + "`",
            "",
            (
                .actions[]
                | "### " + .title,
                  "",
                  "- Status: `" + .status + "`",
                  "- Device: `" + .device + "`",
                  "- Runtime: `" + .runtime + "`",
                  "- Duration: `" + ((.duration * 100 | round / 100) | tostring) + "s`",
                  "- Counts: `passed " + (.passedCount | tostring) + " / failed " + (.failedCount | tostring) + " / skipped " + (.skippedCount | tostring) + " / total " + (.testsCount | tostring) + "`",
                  (
                      if (.suites | length) > 0 then
                          "- Suites:\n" + (.suites | map("  - `" + .name + "` (" + ((.duration * 100 | round / 100) | tostring) + "s)") | join("\n"))
                      else
                          "- Suites: none"
                      end
                  ),
                  (
                      if (.failedTests | length) > 0 then
                          "- Failed tests:\n" + (.failedTests | map("  - `" + .identifier + "`") | join("\n"))
                      else
                          "- Failed tests: none"
                      end
                  ),
                  (
                      if (.failureIssues | length) > 0 then
                          "- Failure issues:\n" + (.failureIssues | map("  - `" + .testCaseName + "`: " + .message) | join("\n"))
                      else
                          "- Failure issues: none"
                      end
                  ),
                  (
                      if (.skippedTests | length) > 0 then
                          "- Skipped tests:\n" + (.skippedTests | map("  - `" + .identifier + "`") | join("\n"))
                      else
                          "- Skipped tests: none"
                      end
                  ),
                  (
                      if (.attachmentReferences | length) > 0 then
                          "- Attachments:\n" + (.attachmentReferences | map("  - `" + (.filename // .name) + "`") | join("\n"))
                      else
                          "- Attachments: none"
                      end
                  ),
                  ""
            )
        ] | join("\n")
    ' <<<"$SUMMARY_JSON"
    exit 0
fi

printf 'xcresult: %s\n' "$RESULT_PATH"

jq -r '
    .actions[] |
    "" +
    "\n" + .title +
    "\nstatus: " + .status +
    " | device: " + .device +
    " | runtime: " + .runtime +
    " | duration: " + ((.duration * 100 | round / 100) | tostring) + "s" +
    " | tests: " + (.testsCount | tostring) +
    " | passed: " + (.passedCount | tostring) +
    " | failed: " + (.failedCount | tostring) +
    " | skipped: " + (.skippedCount | tostring) +
    (
        if (.suites | length) > 0 then
            "\nsuites:\n" + (.suites | map("- " + .name + " (" + ((.duration * 100 | round / 100) | tostring) + "s)") | join("\n"))
        else
            ""
        end
    ) +
    (
        if (.failedTests | length) > 0 then
            "\nfailed tests:\n" + (.failedTests | map("- " + .identifier) | join("\n"))
        else
            ""
        end
    ) +
    (
        if (.failureIssues | length) > 0 then
            "\nfailures:\n" + (.failureIssues | map("- " + .testCaseName + ": " + .message) | join("\n"))
        else
            ""
        end
    ) +
    (
        if (.skippedTests | length) > 0 then
            "\nskipped tests:\n" + (.skippedTests | map("- " + .identifier) | join("\n"))
        else
            ""
        end
    ) +
    (
        if (.attachmentReferences | length) > 0 then
            "\nattachments:\n" + (.attachmentReferences | map("- " + (.filename // .name)) | join("\n"))
        else
            ""
        end
    )
' <<<"$SUMMARY_JSON"
