# iOS Testing Playbook

## Overview

This document is the source of truth for how to run, interpret, and choose iOS tests in this repo.

Current automated surfaces:

- `VoiceCoreTests` for deterministic logic
- `heardTests` for hosted smoke and hosted experimental perf
- `heardUITests` for simulator-driven interaction coverage

Manual validation still remains required for hardware-truth behaviors such as Bluetooth routing, receiver audio, interruptions, and camera fidelity.

## Canonical simulator target

Default local target:

- device: `iPhone 17 Pro`
- runtime: `iOS 26.2`

If `iOS 26.2` is not available, use the nearest current iPhone simulator explicitly instead of relying on Xcode defaults.

## Command matrix

Use `./scripts/test-ios.sh` by default.

### Stable commands

```sh
./scripts/test-ios.sh voicecore
./scripts/test-ios.sh app-build
./scripts/test-ios.sh app-smoke
./scripts/test-ios.sh app-ui
./scripts/test-ios.sh stable
./scripts/test-ios.sh all
```

Meaning:

- `voicecore`: non-performance `VoiceCoreTests`
- `app-build`: hosted app build-for-testing
- `app-smoke`: stable hosted smoke only
- `app-ui`: stable hosted UI classes only
- `stable` and `all`: default full merge gate

### Experimental commands

```sh
./scripts/test-ios.sh app-ui-gestures
./scripts/test-ios.sh app-ui-gestures-repeat 10
./scripts/test-ios.sh experimental
```

Meaning:

- `app-ui-gestures`: gesture-only UI suite
- `app-ui-gestures-repeat 10`: repeated gesture stability run with simulator restart between runs
- `experimental`: VoiceCore perf plus the hosted experimental plan

### Result-bundle commands

```sh
./scripts/xcresult-summary.sh --latest
./scripts/xcresult-summary.sh --latest --json
./scripts/xcresult-summary.sh --latest --markdown
./scripts/xcresult-summary.sh --path <bundle>
./scripts/xcresult-summary.sh --all
./scripts/xcresult-summary.sh --all --json
```

Use the JSON mode for automation and AI triage. Use markdown when writing into CI summaries or PR notes. Use `--all` when you want a gate-level summary across multiple bundles.

## Supported environment variables

These are the supported testing knobs:

- `UITEST_SCENARIO`
- `HEARD_ENABLE_GESTURE_UI_TESTS`
- `IOS_SIMULATOR_ID`
- `IOS_SIMULATOR_DESTINATION`
- `DERIVED_DATA_PATH`

Do not introduce one-off test flags without documenting them here.

## Xcode workflow

### Schemes and plans

Use:

- `VoiceCore` scheme for module logic and VoiceCore perf work
- `heard` scheme with `heard-stable` for smoke and stable UI work
- `heard` scheme with `heard-experimental` for gesture and hosted perf work

Shared plans:

- `app/TestPlans/heard-stable.xctestplan`
- `app/TestPlans/heard-experimental.xctestplan`

### When to use each plan

Use `heard-stable` when:

- validating a product regression before commit
- iterating on smoke tests
- iterating on stable CRUD, navigation, or search UI flows

Use `heard-experimental` when:

- measuring gesture flake
- running hosted performance checks
- investigating simulator-sensitive failures without risking the stable gate

## Test ownership

### `VoiceCoreTests`

Location:

- `Modules/VoiceCore/Tests/VoiceCoreTests/`

Use for:

- coordinators
- audio session policy
- capture and playback behavior
- route state transitions
- deterministic performance hot paths

### `heardTests`

Location:

- `heardTests/`

Use for:

- app-host smoke
- hosted test-mode sanity
- hosted performance checks that stay out of the stable lane

Keep this target smoke-first. Do not treat it as a second logic test suite.

### `heardUITests`

Location:

- `heardUITests/`

Stable coverage currently includes:

- editor open flows
- inventory create, edit, and delete
- recipe open, edit, and delete
- inventory and recipe navigation continuity
- inventory and recipe search/filter coverage

Experimental coverage currently includes:

- keyboard swipe dismissal

## UI-test scenarios

Current scenario names:

- `editor_flows`
- `search_filtering`
- `keyboard_dismiss`
- `empty_state`
- `attachments_basic`

Scenario rules:

- each class should request its scenario explicitly through `UIHarness.launchApp(scenario:)`
- scenarios seed deterministic in-memory data only
- scenario data is reset before each app launch
- future UI flows should reuse or extend scenario fixtures rather than ad hoc launch data

## Perf coverage

Current perf tests:

- `VoiceCorePerformanceTests`
- `AppStartupPerformanceTests`

Current policy:

- perf tests are experimental only
- stable `voicecore` skips `VoiceCorePerformanceTests`
- stable `heard` skips `AppStartupPerformanceTests`
- `./scripts/test-ios.sh experimental` includes VoiceCore perf plus the hosted experimental plan
- current perf values are reference-only because run-to-run variance is still high

Treat current values as instrumentation, not budgets. Review repeated-run spread and relative standard deviation before calling a regression or setting thresholds.

## Result-bundle workflow

After any run:

1. identify the bundle with `--latest` or `--path`
2. read the summary
3. only then read raw logs if the summary is insufficient

Use `--all` when the command produced more than one bundle and you need one machine-readable view of the full run.

### What the summary gives you

- action title
- bundle path
- gate path when using `--all`
- device and runtime
- pass, fail, skip, and total counts
- failed and skipped test identifiers
- failure issue messages
- per-test durations
- attachment filenames when present

### Example

```sh
./scripts/test-ios.sh app-ui
./scripts/xcresult-summary.sh --latest
./scripts/xcresult-summary.sh --latest --json

./scripts/test-ios.sh stable
./scripts/xcresult-summary.sh --all --json
```

## AI failure triage workflow

AI agents should follow this order:

1. run the smallest relevant command
2. inspect `./scripts/xcresult-summary.sh --json`
3. classify the failure
4. decide the next command before rerunning

Failure classes:

- compile/build failure
- module logic failure
- app-host smoke failure
- stable UI regression
- experimental gesture instability
- performance regression

Expected next action by class:

- compile/build failure: fix project or compile issues first
- module logic failure: stay in `VoiceCoreTests`
- smoke failure: inspect `heardTests`, `HeardChefApp`, and test-mode wiring
- stable UI regression: inspect identifiers, scenario seeding, and navigation assumptions
- experimental gesture instability: use `app-ui-gestures-repeat` and attachments before changing the test
- performance regression: rerun the focused perf class and compare observed values before changing budgets

## Promotion rule for experimental tests

Only promote an experimental test into the stable lane when:

- it passes repeated local runs
- it passes repeated CI runs
- it requires no undocumented simulator setting changes
- the result bundle gives actionable failure diagnostics
- adding it keeps the default stable path green and fast enough

At the moment, this rule mainly applies to `KeyboardDismissUITests`.

Current status:

- `KeyboardDismissUITests` is still experimental
- repeated local evidence is mixed rather than decisively green
- do not promote it or describe it as nearly ready until the documented thresholds are actually satisfied

## Preferred verification flows

### VoiceCore logic change

1. `./scripts/test-ios.sh voicecore`
2. if needed, focused `xcodebuild` for one VoiceCore test file
3. if app integration changed, `./scripts/test-ios.sh app-smoke`

### Stable app interaction change

1. `./scripts/test-ios.sh app-build`
2. `./scripts/test-ios.sh app-smoke`
3. `./scripts/test-ios.sh app-ui`
4. `./scripts/xcresult-summary.sh --latest`

### Experimental gesture work

1. `./scripts/test-ios.sh app-ui-gestures`
2. `./scripts/test-ios.sh app-ui-gestures-repeat 10`
3. `./scripts/xcresult-summary.sh --path <failing bundle>`

### Performance work

1. `xcodebuild ... -only-testing:VoiceCoreTests/VoiceCorePerformanceTests`
2. `xcodebuild ... -testPlan heard-experimental -only-testing:heardTests/AppStartupPerformanceTests`
3. compare repeated-run spread before treating any value like a budget

## Manual validation reminders

Still use physical devices for:

- Bluetooth and route truth
- receiver and speaker truth
- CallKit activation and interruption truth
- camera capture fidelity
- richer attachment and media flows
