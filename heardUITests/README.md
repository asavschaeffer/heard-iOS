# heardUITests

This target owns simulator-driven interaction regressions.

## Stable vs experimental

Stable classes belong in the default `app-ui` lane and should be trustworthy enough for CI.

Current stable coverage:

- editor-open flows
- inventory CRUD flows
- recipe CRUD flows
- navigation continuity
- inventory and recipe search/filter regressions

Experimental classes stay opt-in.

Current experimental coverage:

- `KeyboardDismissUITests`

Current status:

- the gesture suite is measurable with repeat tooling
- it is not promotion-ready yet
- failures must remain diagnosable from `.xcresult` before any stable-lane move
- inventory-sheet swipe-down currently has two valid experimental outcomes:
  field focus may blur, or the sheet may dismiss entirely
- this behavior is owned and documented for now, but the UI should eventually
  separate keyboard-dismiss and sheet-dismiss interactions more clearly

Do not move a UI class into the stable lane until it passes repeated runs and produces actionable diagnostics when it fails.

## Known follow-up

- Resolve the inventory sheet gesture overlap so swipe-down-to-dismiss-keyboard
  does not also act like swipe-down-to-dismiss-sheet in the same interaction path.

## Scenarios

Every UI test should launch the app with `-ui-testing` and an explicit `UITEST_SCENARIO`.

Current named scenarios:

- `editor_flows`
- `search_filtering`
- `keyboard_dismiss`
- `empty_state`
- `attachments_basic`

Rules:

- request the scenario explicitly through `UIHarness.launchApp(scenario:)`
- keep scenario data deterministic and in-memory only
- add fixture data through the app-side scenario fixtures, not ad hoc inside the test

## Use this target for

- modal presentation and dismissal
- stable CRUD and navigation regressions
- destructive confirmation flows
- search and filtering regressions
- simulator-safe future attachment happy paths

## Do not use this target for

- pure logic that belongs in module tests
- app boot sanity that belongs in `heardTests`
- route or camera truth that still needs device validation

## Commands

Stable:

- `./scripts/test-ios.sh app-ui`

Experimental:

- `./scripts/test-ios.sh app-ui-gestures`
- `./scripts/test-ios.sh app-ui-gestures-repeat 10`

Diagnostics:

- `./scripts/xcresult-summary.sh --latest`
- `./scripts/xcresult-summary.sh --latest --json`
- `./scripts/xcresult-summary.sh --all`
- `./scripts/xcresult-summary.sh --all --json`

## Gesture promotion rule

Gesture-heavy regressions stay experimental until:

- they pass repeated local runs
- they pass repeated CI runs
- they need no undocumented simulator setup
- their failures are diagnosable from `.xcresult`
