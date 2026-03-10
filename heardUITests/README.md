# heardUITests

This target owns simulator-driven interaction regressions.

Use it for:

- modal presentation and dismissal
- stable editor and navigation flows
- opt-in keyboard dismissal behavior
- navigation flows
- destructive confirmation flows

Do not use it for:

- pure logic that belongs in module tests
- app boot sanity that belongs in `heardTests`
- hardware-sensitive audio or camera truth that still needs device validation

The tests in this target should launch the app with `-ui-testing` and a deterministic `UITEST_SCENARIO`.

Default `app-ui` runs should stay green and stable.

Gesture-heavy regressions that are still simulator-sensitive should be opt-in and skipped unless explicitly enabled via `HEARD_ENABLE_GESTURE_UI_TESTS=1`.
