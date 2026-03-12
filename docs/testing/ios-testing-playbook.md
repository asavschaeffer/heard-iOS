# iOS Testing Playbook

This document is the source of truth for how iOS tests are organized, run, and interpreted in this repo.

## Goals

The test setup must work cleanly in four places:

- Xcode while iterating locally
- `./scripts/test-ios.sh` for deterministic CLI verification
- CI for the default merge gate
- AI workflows that need an explicit command matrix and machine-readable diagnostics

## Framework policy

Use the native framework that matches the surface under test:

- Swift Testing for non-UI unit, integration, and hosted tests
- XCTest for UI tests
- XCTest for performance tests that use `measure`

Current toolchain assumptions:

- Xcode 17.x
- Apple Swift 6.2 toolchain
- project source currently builds in Swift 5 language mode

## Automated surfaces

### `VoiceCoreTests`

Location:

- `Modules/VoiceCore/Tests/VoiceCoreTests/`

Use for:

- coordinators
- audio session policy
- capture and playback behavior
- route state transitions
- deterministic async behavior

Current framework split:

- Swift Testing for logic tests
- XCTest for `VoiceCorePerformanceTests`

### `heardTests`

Location:

- `heardTests/`

Use for:

- app-host boot sanity
- test-mode sanity
- lightweight hosted configuration and wiring checks
- hosted performance checks that stay out of the stable lane

Stable hosted coverage currently includes:

- `AppLaunchSmokeTests`
- `GeminiServiceSetupTests`

Experimental hosted coverage currently includes:

- `AppStartupPerformanceTests`

### `heardUITests`

Location:

- `heardUITests/`

Use for:

- simulator-driven CRUD flows
- navigation regressions
- search and filtering regressions
- destructive confirmation flows
- experimental gesture regressions

Stable UI coverage currently includes:

- `EditorFlowUITests`
- `InventoryFlowUITests`
- `RecipeFlowUITests`
- `NavigationUITests`
- `SearchFilteringUITests`

Experimental UI coverage currently includes:

- `KeyboardDismissUITests`

## Stable and experimental lanes

### Stable lane

Commands:

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
- `app-build`: shared hosted build-for-testing path
- `app-smoke`: stable hosted lane for `heardTests`
- `app-ui`: stable `heardUITests` classes only
- `stable` and `all`: default full merge gate

### Experimental lane

Commands:

```sh
./scripts/test-ios.sh app-ui-gestures
./scripts/test-ios.sh app-ui-gestures-repeat 10
./scripts/test-ios.sh experimental
```

Meaning:

- `app-ui-gestures`: gesture-only UI suite
- `app-ui-gestures-repeat 10`: repeated gesture reliability run
- `experimental`: VoiceCore perf plus the hosted experimental plan

Performance tests remain experimental until the repo has enough repeated-run evidence to treat them as budgets rather than instrumentation.

## Xcode-native workflow

Use:

- `VoiceCore` scheme for module logic and VoiceCore perf
- `heard` scheme with `heard-stable` for default hosted and stable UI work
- `heard` scheme with `heard-experimental` for gesture and hosted perf work

Shared plans:

- `app/TestPlans/heard-stable.xctestplan`
- `app/TestPlans/heard-experimental.xctestplan`

The Xcode-native default path is the shared `heard-stable` plan plus the standalone `VoiceCore` scheme.

## Canonical simulator target

Preferred default target:

- device: `iPhone 17 Pro`
- runtime: `iOS 26.2`

`scripts/test-ios.sh` resolves the simulator in this order:

1. `IOS_SIMULATOR_DESTINATION`
2. `IOS_SIMULATOR_ID`
3. exact `iPhone 17 Pro` on `iOS 26.2`
4. `iPhone 17 Pro` on the newest installed iOS runtime
5. newest available iPhone simulator

The script prints the destination it selected before running tests.

## Supported environment variables

- `UITEST_SCENARIO`
- `HEARD_ENABLE_GESTURE_UI_TESTS`
- `IOS_SIMULATOR_ID`
- `IOS_SIMULATOR_DESTINATION`
- `DERIVED_DATA_PATH`

Do not introduce one-off test flags without documenting them here.

## UI-test scenarios

Every UI test should launch through `UIHarness.launchApp(scenario:)`.

Current scenario names:

- `editor_flows`
- `search_filtering`
- `keyboard_dismiss`
- `empty_state`
- `attachments_basic`

Rules:

- each class requests the scenario it needs explicitly
- scenario data stays deterministic and in-memory only
- scenario data is reset before each app launch
- new UI coverage should extend scenario fixtures rather than ad hoc launch data

## Result-bundle workflow

After any run:

1. identify the bundle with `--latest`, `--path`, or `--all`
2. read the `.xcresult` summary
3. only then fall back to raw `xcodebuild` logs

Commands:

```sh
./scripts/xcresult-summary.sh --latest
./scripts/xcresult-summary.sh --latest --json
./scripts/xcresult-summary.sh --latest --markdown
./scripts/xcresult-summary.sh --path <bundle>
./scripts/xcresult-summary.sh --all
./scripts/xcresult-summary.sh --all --json
```

Use JSON for automation and AI triage. Use markdown for CI or PR summaries.

## AI failure triage workflow

AI agents should follow this order:

1. run the smallest relevant command
2. inspect `./scripts/xcresult-summary.sh --json`
3. classify the failure
4. decide the next command before rerunning

Failure classes:

- compile/build failure
- module logic failure
- app-host failure
- stable UI regression
- experimental gesture instability
- performance regression

Expected next action by class:

- compile/build failure: fix project or compile issues first
- module logic failure: stay in `VoiceCoreTests`
- app-host failure: inspect `heardTests`, `HeardChefApp`, and hosted wiring
- stable UI regression: inspect identifiers, scenario seeding, and navigation assumptions
- experimental gesture instability: use repeated runs and `.xcresult` attachments before changing coverage
- performance regression: rerun the focused perf class before changing any budget language

## Promotion rule for experimental tests

Only promote an experimental test into the stable lane when:

- it passes repeated local runs
- it passes repeated CI runs
- it needs no undocumented simulator setup
- failures are diagnosable from `.xcresult`
- adding it keeps the stable path trustworthy and fast enough

This currently applies most directly to `KeyboardDismissUITests`.

Current note:

- the inventory add/edit sheets still allow two valid experimental swipe-down outcomes:
  - the focused field blurs
  - the sheet dismisses entirely
- this remains an owned experimental behavior overlap, not stable-lane semantics

## Preferred verification flows

### VoiceCore logic change

1. `./scripts/test-ios.sh voicecore`
2. if app integration changed, `./scripts/test-ios.sh app-smoke`

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
3. compare repeated-run spread before treating a value like a budget

## Manual validation reminders

Still use physical devices for:

- Bluetooth and route truth
- receiver and speaker truth
- CallKit activation and interruption truth
- camera capture fidelity
- richer attachment and media flows
