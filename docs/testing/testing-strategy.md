# iOS Testing Strategy

## Why this exists

The repo needs one testing model that works in four places:

- Xcode while developing locally
- the CLI for deterministic local verification
- CI for the default merge gate
- AI agents that need to choose the right command and read failures without guessing

The goal is not maximal automation. The goal is a trustworthy default path, a clearly isolated experimental path, and result bundles that explain what happened.

## Current testing model

Use four layers.

### 1. Module logic tests

Primary location:

- `Modules/VoiceCore/Tests/VoiceCoreTests/`

Use this layer for:

- coordinators and state machines
- route policy decisions
- capture and playback fallback behavior
- deterministic async and lifecycle transitions
- measure-based subsystem performance checks

This remains the primary automated gate for voice behavior.

### 2. App-host smoke tests

Primary location:

- `heardTests/`

Use this layer for:

- app boot sanity in test mode
- hosted wiring checks
- lightweight app-shell integration validation

Do not move business logic into this target. It should remain smoke-first.

### 3. Simulator UI automation

Primary location:

- `heardUITests/`

Use this layer for:

- stable CRUD flows
- navigation regressions
- search and filtering regressions
- destructive confirmation flows
- experimental gesture regressions

Stable UI tests are part of the default green path. Gesture-heavy regressions remain experimental until they meet explicit promotion criteria.

### 4. Physical-device validation

Keep device-only validation for:

- Bluetooth, receiver, and speaker route truth
- CallKit activation and deactivation truth
- interruption handling
- camera fidelity
- richer attachment and media fidelity

Manual does not mean vague. These checks must stay documented and repeatable.

## Stable vs experimental lanes

This repo now has a first-class stable and experimental split.

### Stable lane

Purpose:

- default local verification
- default CI gate
- default Xcode testing path for the shared `heard` plan

Current stable commands:

- `./scripts/test-ios.sh voicecore`
- `./scripts/test-ios.sh app-build`
- `./scripts/test-ios.sh app-smoke`
- `./scripts/test-ios.sh app-ui`
- `./scripts/test-ios.sh stable`
- `./scripts/test-ios.sh all`

Current stable coverage:

- all non-performance `VoiceCoreTests`
- `heardTests/Smoke/AppLaunchSmokeTests`
- stable `heardUITests` classes:
  - `EditorFlowUITests`
  - `InventoryFlowUITests`
  - `RecipeFlowUITests`
  - `NavigationUITests`
  - `SearchFilteringUITests`

### Experimental lane

Purpose:

- opt-in simulator-sensitive coverage
- performance coverage that is not yet part of the PR gate
- repeated reliability investigation

Current experimental commands:

- `./scripts/test-ios.sh app-ui-gestures`
- `./scripts/test-ios.sh app-ui-gestures-repeat 10`
- `./scripts/test-ios.sh experimental`

Current experimental coverage:

- `KeyboardDismissUITests`
- `VoiceCorePerformanceTests`
- `heardTests/Smoke/AppStartupPerformanceTests`

### Xcode-native plan usage

Shared plans live under:

- `app/TestPlans/heard-stable.xctestplan`
- `app/TestPlans/heard-experimental.xctestplan`

Use:

- `heard-stable` for default hosted smoke and stable UI work
- `heard-experimental` for gesture and hosted perf checks

Keep `VoiceCore` on its own scheme. Do not merge logic coverage into hosted targets.

## Decision rule: where should a new test go?

Ask these questions in order:

1. Can this behavior be validated without launching the app?
2. Does the failure mainly indicate logic, hosted wiring, UI, or hardware truth?
3. Is the behavior simulator-stable enough to trust in the default gate?

Use the first matching home:

- deterministic subsystem behavior: module tests
- app boot or host wiring behavior: `heardTests`
- stable UI regression: stable `heardUITests`
- simulator-sensitive UI or performance candidate: experimental lane
- hardware truth: manual device checklist

## Fixture and scenario rules

UI-test data must now be declared by scenario, not by accidental shared seeding.

Current named scenarios:

- `editor_flows`
- `search_filtering`
- `keyboard_dismiss`
- `empty_state`
- `attachments_basic`

Rules:

- each scenario seeds only the data it needs
- seeding remains in-memory only
- each scenario is deterministic and reset before use
- tests should request the scenario they depend on explicitly through `UIHarness`
- future simulator-safe attachment coverage should extend `attachments_basic` instead of inventing ad hoc launch data

## Result bundles as the diagnostics interface

`.xcresult` is now the first place to look after any test run.

Primary commands:

- `./scripts/xcresult-summary.sh --latest`
- `./scripts/xcresult-summary.sh --latest --json`
- `./scripts/xcresult-summary.sh --latest --markdown`
- `./scripts/xcresult-summary.sh --path <bundle>`
- `./scripts/xcresult-summary.sh --all`
- `./scripts/xcresult-summary.sh --all --json`

Use result bundles for:

- status, counts, runtime, and device metadata
- failed and skipped test lists
- failure issue messages
- per-test durations
- UI attachments such as screen recordings, synthesized events, and failure screenshots

AI and humans should inspect the result bundle summary before reading raw xcodebuild logs.

Use `--latest` or `--path` when you are triaging one specific bundle. Use `--all` when you need a gate-level view across multiple bundles, such as the default stable CI run.

## AI operating model

AI agents should follow this flow:

1. Run the smallest relevant test command.
2. Read `./scripts/xcresult-summary.sh --json`.
3. Classify the failure before rerunning anything.
4. Choose the next action based on that classification.

Current classification buckets:

- compile or build failure
- module logic failure
- app-host smoke failure
- stable UI regression
- experimental gesture instability
- performance regression

Expected next actions:

- build failure: fix compile or project wiring first
- module logic failure: stay in `VoiceCoreTests`
- smoke failure: inspect hosted app startup and test-mode wiring
- stable UI regression: inspect identifiers, scenario data, or navigation state
- experimental gesture instability: use repeat tooling and attachment diagnostics before changing stable coverage
- performance regression: reproduce with the focused perf class before changing budgets

## Performance policy

Performance tests exist, but they are not part of the default merge gate yet.

Current performance coverage:

- `VoiceCorePerformanceTests`
- `AppStartupPerformanceTests`

Policy:

- keep perf tests in the experimental lane until budgets and hardware expectations settle
- use `measure {}` only around deterministic hot paths
- document observed numbers and variance before turning perf regressions into a hard gate

Current status:

- the perf classes pass
- relative standard deviation is still high enough that the numbers should be treated as investigation aids, not release budgets
- any future budget work must be based on repeated runs and variance review, not one clean sample

## Promotion rule for experimental tests

Experimental tests only graduate into the stable lane when:

- they pass repeated local simulator runs
- they pass repeated CI runs
- they need no undocumented simulator tweaks
- their failures are diagnosable from the result bundle
- adding them does not break the default green path

This rule currently applies most directly to `KeyboardDismissUITests`.

Current status:

- `KeyboardDismissUITests` remains experimental
- repeat-run evidence is mixed rather than cleanly green
- the class should not be described as promotion-ready until the documented local and CI thresholds are actually met
- inventory-sheet swipe-down currently has overlapping outcomes in simulator
  automation: focus may blur or the sheet may dismiss
- that overlap is a known product-behavior follow-up, so the experimental suite
  treats either outcome as success while the interaction remains unresolved

## Reliability rules

Keep these rules in force:

- prefer the script entrypoint over ad hoc xcodebuild commands
- keep stable and experimental coverage intentionally separate
- do not add flaky timing-heavy checks to `heardTests`
- do not add simulator-sensitive regressions to the stable UI lane
- inspect `.xcresult` before raw logs
- document every manual-only area so "manual" remains repeatable
