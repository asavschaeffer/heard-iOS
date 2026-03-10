# heardTests

This target is intentionally smoke-only.

Use it for:

- app-host boot checks
- test-mode sanity checks
- lightweight wiring verification

Do not use it for:

- subsystem logic that belongs in module tests
- heavy async integration tests
- gesture and navigation regressions that belong in `heardUITests`

Preferred layout:

- `Smoke/` for the actual hosted checks
- `Support/` for factories and helpers when the target needs them
