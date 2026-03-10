# iOS Testing Playbook

## Overview

This document is the source of truth for how to test the app today.

There are three active test surfaces today:

- `VoiceCoreTests`: the primary automated logic suite for voice/call behavior
- `heardTests`: a smoke-only app-hosted suite
- manual device validation: required for route-sensitive audio behavior and richer AI attachment flows

There is also a UI interaction test surface:

- `heardUITests`: simulator-driven interaction coverage for stable editor flows, modal flows, and opt-in keyboard regressions

The current automation split is intentional:

- reusable subsystem behavior lives in `Modules/VoiceCore/Tests/VoiceCoreTests/`
- app-host coverage stays minimal in `heardTests/`
- physical device checks remain mandatory for receiver, speaker, Bluetooth, CallKit, and interruption flows

## Canonical Local Target

Use this simulator target as the default local CLI destination:

- model: `iPhone 17 Pro`
- runtime: `iOS 26.2`

If that runtime is not installed on a machine, choose the nearest current iPhone simulator and update the command explicitly instead of relying on Xcode defaults.

## Quick Start

Use the shared script entrypoint by default:

```sh
./scripts/test-ios.sh voicecore
./scripts/test-ios.sh app-build
./scripts/test-ios.sh app-smoke
./scripts/test-ios.sh app-ui
./scripts/test-ios.sh app-ui-gestures
./scripts/test-ios.sh all
./scripts/xcresult-summary.sh --latest
```

The script is the preferred entrypoint for local CLI use, AI agents, and CI because it resolves a concrete simulator, boots it ahead of time, and creates a placeholder `Secrets.xcconfig` when a machine does not already have one.

Raw `xcodebuild` commands remain useful when you want tighter control.

Use `./scripts/xcresult-summary.sh --latest` after a run when you want a compact summary of the newest result bundle, or `--json` when you want machine-readable output for automation.

### Run `VoiceCore` tests

```sh
xcodebuild -project app/HeardChef.xcodeproj -scheme VoiceCore -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test
```

Use this as the default automated suite for voice-stack work.

### Run `heard` smoke tests

```sh
xcodebuild -project app/HeardChef.xcodeproj -scheme heard -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test
```

This validates that the app host and test harness still boot correctly.

### Run `heard` build-for-testing

```sh
xcodebuild -project app/HeardChef.xcodeproj -scheme heard -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' build-for-testing
```

Use this for fast host validation when you want to confirm the app target, test bundle, and simulator destination still build cleanly without paying for a full hosted test run.

### Important: always provide a simulator destination

Do not rely on plain `xcodebuild test` without `-destination`.

Why:

- Xcode can select the wrong platform by default
- app code depends on iOS-only frameworks such as `CallKit` and `AVAudioSession`
- omitting `-destination` can lead to misleading failures that are not product regressions

## Test Targets and Responsibilities

### `VoiceCoreTests`

Location:

- `Modules/VoiceCore/Tests/VoiceCoreTests/`

This is the primary automated logic surface.

Responsibilities:

- call coordinator behavior
- audio session and route policy decisions
- capture fallback behavior
- playback queue and restart behavior
- explicit call and route state machine coverage

### `heardTests`

Location:

- `heardTests/`

This is intentionally smoke-only.

Allowed coverage:

- app launches in test mode
- the app-host test harness boots correctly
- `TestSupport` test mode keeps startup lightweight
- minimal host integration sanity checks

Not allowed:

- subsystem logic tests
- audio route policy tests
- heavy async transport tests
- attachment or media fixture logic tests unless they are explicitly app-host smoke checks

### `heardUITests`

Location:

- `heardUITests/`

This target owns simulator-driven interaction regressions.

Current coverage:

- stable editor-open coverage in add ingredient, edit ingredient, and edit recipe flows
- opt-in keyboard dismissal coverage for those same flows

Recommended future coverage:

- modal and sheet regressions
- stable navigation and editor regressions by default
- gesture-based keyboard dismissal regressions once they stabilize in simulator
- navigation path regressions
- confirmation dialog flows
- stable simulator-safe attachment happy paths

## Current Known Constraints

- Simulator success does not prove receiver, speaker, Bluetooth, or CallKit route correctness.
- Physical-device testing is still required for route-sensitive audio behavior.
- Media-heavy AI flows are only partially automatable today.
- Attachment flows can be exercised in simulator and on device, but they are not yet backed by a committed deterministic fixture suite.

### Test execution speed

- `VoiceCoreTests` is a non-hosted bundle — tests themselves run in ~0.1s, but simulator boot and xcodebuild overhead add 15–25s wall time on a warm simulator.
- `heardTests` is hosted — it launches the full app binary (in test mode), so expect 60–90s wall time even though the test logic is instant.
- `heardUITests` is also hosted and drives the simulator UI, so expect it to be the slowest and most failure-sensitive layer.
- **Boot the simulator first** to avoid cold-boot delays and transient "Invalid device state" errors:
  ```sh
  xcrun simctl boot "iPhone 17 Pro" 2>/dev/null
  ```
- For faster iteration, run `VoiceCoreTests` alone. Only run `heardTests` when validating app-host integration.
- Run `heardUITests` when the change touches user interaction or when doing full pre-merge verification.
- Run `./scripts/test-ios.sh app-ui-gestures` only when you explicitly want the experimental keyboard-dismiss regression pass.
- When running from CLI (AI agents, CI), target a specific scheme (`-only-testing:VoiceCoreTests` or `-only-testing:heardTests`) to avoid running both suites every time.
- If local gesture UI keyboard tests do not show a software keyboard, disable `I/O > Keyboard > Connect Hardware Keyboard` in Simulator and rerun.
- CI now uploads `.xcresult` bundles as artifacts, so failure triage should start from the preserved result bundle rather than raw log text alone.

## Directory Conventions

- `Modules/<Module>/Tests/<Module>Tests/` owns deterministic subsystem coverage
- `heardTests/Smoke/` owns app-host smoke checks
- `heardTests/Support/` is reserved for helpers and factories
- `heardUITests/Scenarios/` owns user-flow regressions
- `heardUITests/Support/` owns UI harness helpers
- `docs/testing/testing-strategy.md` explains the ownership model

## Test Mode App Behavior

The app now has an explicit lightweight test mode.

Relevant files:

- `app/TestSupport.swift`
- `app/HeardChefApp.swift`

Current behavior during tests:

- `TestSupport` detects XCTest launch conditions
- SwiftData uses an in-memory `ModelConfiguration`
- `HeardChefApp` renders `Color.clear` instead of booting the full warmup/UI stack
- warmup tasks do not run in test mode

This is why `heardTests` should stay narrow and deterministic.

## Manual Validation Matrix

For voice-stack validation, use:

- `docs/rebuild/04-voice-regression-matrix.md`

That document is the physical-device checklist for:

- receiver and speaker switching
- Bluetooth and wired route changes
- background/foreground transitions
- CallKit mute and interruption behavior

### Attachment Validation Checklist

Run these manually before merging AI attachment or media-ingestion changes:

- attach an image from Photos and confirm it appears in the composer and is sent successfully
- attach a short video and confirm preview, upload, and Gemini-side handling still work
- exercise the Photos picker on simulator and device
- exercise camera capture flow if the feature is still enabled in the current build
- confirm attachment failures produce user-visible errors instead of silent drops

## Local Fixture Workflow

Real media fixtures are local-only and intentionally excluded from git.

Canonical local fixture root:

- `TestFixtures.local/`

Expected layout:

- `TestFixtures.local/audio/`
- `TestFixtures.local/video/`
- `TestFixtures.local/images/`

Recommended formats:

- audio: `.wav`, mono preferred, 48 kHz preferred
- video: short `.mov` or `.mp4`, small filesize
- images: `.jpg` or `.png`

Recommended starter set:

- `TestFixtures.local/audio/normal-speech.wav`
- `TestFixtures.local/audio/short-utterance.wav`
- `TestFixtures.local/audio/pause-middle.wav`
- `TestFixtures.local/audio/room-noise.wav`
- `TestFixtures.local/video/short-demo.mov`
- `TestFixtures.local/images/kitchen-counter.jpg`
- `TestFixtures.local/images/ingredient-closeup.jpg`

Current intended usage:

- manual simulator runs
- manual device validation
- future smoke automation

Not intended yet:

- deterministic unit-test dependencies
- committed repo fixtures

## Diagnostics and Logs

Voice diagnostics are funneled through `VoiceDiagnostics`.

Current logging expectations:

- debug builds: verbose audio, route, CallKit, and Gemini lifecycle logs are available
- release builds: verbose traces should stay quiet and only faults/errors should remain

Useful places to inspect behavior:

- Xcode test output for `VoiceCore` and `heard`
- simulator/device console logs
- runtime logs from `VoiceDiagnostics`

When debugging route-sensitive bugs, always correlate:

- route changes
- CallKit activation/deactivation
- capture start/stop
- playback start/stop
- Gemini websocket lifecycle

## Future Automation Goals

- simulator-driven smoke scenarios for AI attachment flows
- local fixture-backed smoke checks for image/video/audio ingestion
- broader deterministic harnesses for Gemini-related feature flows
- deeper state-machine coverage inside `VoiceCore`

## Preferred Verification Flow

### Voice-Only Changes

1. Run `VoiceCore` tests.
2. Run `heard` `build-for-testing` with the canonical simulator destination.
3. Run `heard` smoke tests if the change touches app-side integration.
4. Run the manual device checklist in `docs/rebuild/04-voice-regression-matrix.md`.

### App-Host Changes

1. Run `heard` `build-for-testing` with the canonical simulator destination.
2. Run `heard` smoke tests.
3. Run `heardUITests` if the change touches user interaction.
4. Run the relevant module tests.
5. Verify test mode still boots cleanly.

### Attachment / Media Changes

1. Run `heard` `build-for-testing` with the canonical simulator destination.
2. Run `heard` smoke tests.
3. Exercise local fixtures manually from `TestFixtures.local/`.
4. Validate image/video flows on a physical device when camera or route-sensitive behavior is involved.
