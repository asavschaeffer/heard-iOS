# heardTests

This target owns hosted, non-UI app checks.

Canonical guidance lives in [docs/testing/ios-testing-playbook.md](../docs/testing/ios-testing-playbook.md).

## Use this target for

- app-host boot checks
- test-mode sanity checks
- lightweight hosted configuration and wiring validation
- hosted performance checks that remain experimental

## Stable hosted coverage

- `AppLaunchSmokeTests`
- `GeminiServiceSetupTests`

`GeminiServiceSetupTests` validates the hosted setup payload matrix for the current default audio profile plus explicitly modeled alternative profiles.

## Experimental hosted coverage

- `AppStartupPerformanceTests`

## Commands

Stable hosted lane:

- `./scripts/test-ios.sh app-smoke`

Preferred summaries:

- `./scripts/xcresult-summary.sh --latest-run --json`
- `./scripts/xcresult-summary.sh --run <run-id> --json`

Focused hosted perf:

- `xcodebuild -project app/HeardChef.xcodeproj -scheme heard -testPlan heard-experimental -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' test -only-testing:heardTests/AppStartupPerformanceTests`
