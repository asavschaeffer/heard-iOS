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

Current named scenarios:

- `editor_flows` for stable editor, CRUD, and navigation coverage
- `search_filtering` for stable inventory and recipe search/filter coverage
- `keyboard_dismiss` for opt-in gesture dismissal checks
- `empty_state` reserved for future empty-state coverage
- `attachments_basic` reserved for future attachment/media coverage

Default `app-ui` runs should stay green and stable.

Gesture-heavy regressions that are still simulator-sensitive should be opt-in and skipped unless explicitly enabled via `HEARD_ENABLE_GESTURE_UI_TESTS=1`.
