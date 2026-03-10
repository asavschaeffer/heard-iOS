# iOS Testing Strategy

## Why this exists

The repo needs a testing model that is easy to reason about in three contexts:

- inside Xcode while learning the platform
- from the CLI for repeatable local verification
- from AI agents and CI without tribal knowledge

The goal is not "maximum number of tests." The goal is fast, trustworthy feedback with clear ownership.

## The testing model

Use four layers.

### 1. Module logic tests

Put deterministic behavior in module-owned tests first.

Current example:

- `Modules/VoiceCore/Tests/VoiceCoreTests/`

Use this layer for:

- state machines
- reducers and coordinators
- route policy decisions
- async retry and fallback behavior
- parsing, normalization, and transformation logic

This should be the default destination for new automation whenever the behavior can be expressed without a full app launch.

### 2. App-host smoke tests

Keep hosted app tests narrow and cheap.

Current location:

- `heardTests/`

Use this layer for:

- test-mode boot sanity
- app-host wiring checks
- lightweight persistence boot checks
- regression checks that need the app target to exist but do not need UI gestures

Do not let this target absorb deep business logic. If logic is reusable enough to deserve real coverage, move it into a module or another testable seam.

### 3. UI automation

This repo now has a dedicated `heardUITests/` target.

That target should own:

- modal presentation regressions
- stable editor and navigation regressions
- opt-in keyboard dismissal regressions
- navigation flows
- destructive confirmation flows
- basic attachment happy-path checks that can run in simulator

The first stable committed scenarios are editor-open flows for ingredient and recipe sheets.

Keyboard-dismiss regressions for those sheets also exist, but they are intentionally opt-in today because simulator gesture behavior is still too variable to make them trustworthy as default CI gates.

### 4. Physical-device validation

Some truths are still hardware truths.

Keep device validation for:

- CallKit activation/deactivation
- receiver/speaker/Bluetooth routing
- interruption handling
- microphone and camera permission flows
- camera capture flows
- richer attachment and media behavior where simulator fidelity is weak

Manual does not mean vague. Manual checks should be documented as repeatable checklists.

## Decision rule: where should a new test go?

Ask these questions in order:

1. Can the behavior be validated without launching the app?
2. Can the behavior be represented as deterministic inputs and outputs?
3. Does the failure primarily indicate a subsystem bug, app wiring bug, UI bug, or hardware/platform issue?

Use the first matching home:

- deterministic subsystem behavior: module tests
- app boot or host wiring behavior: `heardTests`
- gesture/navigation/view regression: `heardUITests`
- hardware-sensitive behavior: manual device checklist

## Directory conventions

The repo should converge on this shape:

```text
Modules/
  <Module>/
    Sources/
    Tests/
      <Module>Tests/
        Support/

heardTests/
  Smoke/
  Support/

heardUITests/
  Scenarios/
  Support/

docs/testing/
  ios-testing-playbook.md
  testing-strategy.md
```

Notes:

- module tests live with the module that owns the logic
- `heardTests/Smoke/` stays intentionally small
- `heardTests/Support/` is for shared factories and harness helpers only
- `heardUITests/Scenarios/` contains the interaction tests
- `heardUITests/Support/` contains launch and wait helpers

## Naming conventions

Prefer names that say what kind of test they are.

Examples:

- `VoiceCallCoordinatorTests.swift`
- `AppLaunchSmokeTests.swift`
- `IngredientEditorUITests.swift`
- `AttachmentComposerUITests.swift`

Avoid generic names like `heardTests.swift` once a target has more than one file.

## What “good coverage” means here

Coverage quality is about risk reduction, not percentage chasing.

For this app, a strong testing posture means:

- stateful voice logic is heavily covered in `VoiceCoreTests`
- the app host proves it can boot in test mode
- major interaction regressions get a UI test once a flow becomes stable enough
- route-sensitive and media-sensitive behavior still gets device validation

## Recommended workflow in Xcode

Use Xcode for focused iteration, not just one giant Test command.

Practical habits:

- run a single test method while developing a fix
- run one test file before running the whole target
- switch schemes intentionally: `VoiceCore` for module work, `heard` for app-host checks
- use the Test navigator to rerun only failures after a larger run
- keep hosted app tests separate from pure logic tests mentally and structurally

## Recommended workflow for AI agents and CLI

Use the script entrypoint:

- `./scripts/test-ios.sh voicecore`
- `./scripts/test-ios.sh app-build`
- `./scripts/test-ios.sh app-smoke`
- `./scripts/test-ios.sh app-ui`
- `./scripts/test-ios.sh app-ui-gestures`
- `./scripts/test-ios.sh all`
- `./scripts/xcresult-summary.sh --latest`

Why:

- the script chooses a concrete simulator destination
- it boots the simulator up front
- it creates a temporary placeholder `Secrets.xcconfig` when needed
- CI, AI agents, and local terminal usage all share the same commands
- `xcresult-summary.sh` gives both humans and AI a compact view of the latest result bundle, with optional JSON output for automation

Local note:

- Stable `app-ui` runs should stay green in CI and for AI agents.
- Gesture keyboard tests are opt-in via `./scripts/test-ios.sh app-ui-gestures`.
- If local gesture runs fail because no software keyboard appears, disable `I/O > Keyboard > Connect Hardware Keyboard` in Simulator and rerun.

## Reliability rules

Keep these rules in force:

- always pass an explicit simulator destination or use the script that resolves one
- prefer module tests over hosted tests when both are possible
- do not add flaky timing-heavy tests to `heardTests`
- add UI automation only for flows that are stable enough to maintain
- document every manual-only area so “manual” stays repeatable

## Near-term roadmap

1. Keep growing `VoiceCoreTests` for route and lifecycle logic.
2. Keep `heardTests` limited to smoke and boot checks.
3. Keep expanding stable `heardUITests` coverage for sheet and navigation regressions.
4. Promote gesture regressions from opt-in to default only after they prove stable across repeated simulator runs.
5. Add fixture-backed simulator coverage for attachment happy paths once the flow stabilizes.
6. Keep device-only checklists for audio and camera truth.
