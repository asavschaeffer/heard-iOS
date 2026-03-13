# heardUITests

This target owns simulator-driven interaction regressions.

Canonical guidance lives in [docs/testing/ios-testing-playbook.md](../docs/testing/ios-testing-playbook.md).

## Stable UI coverage

- `EditorFlowUITests`
- `InventoryFlowUITests`
- `RecipeFlowUITests`
- `NavigationUITests`
- `SearchFilteringUITests`

## Experimental UI coverage

- `KeyboardDismissUITests`

## Commands

Stable:

- `./scripts/test-ios.sh app-ui`

Experimental:

- `./scripts/test-ios.sh app-ui-gestures`
- `./scripts/test-ios.sh app-ui-gestures-repeat 10`

Diagnostics:

- `./scripts/xcresult-summary.sh --latest-run`
- `./scripts/xcresult-summary.sh --latest-run --json`
- `./scripts/xcresult-summary.sh --run <run-id>`
- `./scripts/xcresult-summary.sh --run <run-id> --json`
- `./scripts/xcresult-summary.sh --latest`
- `./scripts/xcresult-summary.sh --latest --json`
- `./scripts/xcresult-summary.sh --all`
- `./scripts/xcresult-summary.sh --all --json`

## Notes

- UI tests stay on XCTest
- `UIHarness.launchApp(scenario:)` is the required entrypoint for scenario seeding
- `HEARD_SKIP_WARMUP=0` enables the real launch overlay path for dedicated launch coverage
- `--latest-run` is the preferred summary mode for one logical verification pass; `--all` is historical aggregation
- gesture-heavy coverage remains experimental until repeated runs and `.xcresult` diagnostics make it stable-lane worthy
