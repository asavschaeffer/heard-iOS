# heardTests

This target is intentionally hosted and intentionally small.

## Purpose

Use `heardTests` for:

- app-host boot checks
- test-mode sanity checks
- lightweight wiring verification
- hosted experimental performance checks

Do not use it for:

- subsystem logic that belongs in module tests
- gesture and navigation regressions that belong in `heardUITests`
- heavy async integration tests

## Stable vs experimental

Stable hosted coverage:

- `AppLaunchSmokeTests`

Experimental hosted coverage:

- `AppStartupPerformanceTests`

The stable `heard` plan skips `AppStartupPerformanceTests` so `app-smoke` remains smoke-only.

The experimental `heard` plan skips `AppLaunchSmokeTests` so hosted perf work can run without duplicating stable smoke.

## Commands

Stable:

- `./scripts/test-ios.sh app-smoke`

Focused hosted perf:

- `xcodebuild -project app/HeardChef.xcodeproj -scheme heard -testPlan heard-experimental -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:heardTests/AppStartupPerformanceTests`

## Layout

- `Smoke/` for hosted tests
- `Support/` for helper code only when needed
