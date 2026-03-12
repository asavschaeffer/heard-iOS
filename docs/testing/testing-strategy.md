# iOS Testing Strategy

Use [docs/testing/ios-testing-playbook.md](./ios-testing-playbook.md) as the operational source of truth.

This file exists only to capture the high-level intent behind the current structure:

- keep `VoiceCoreTests` as the primary automated logic surface
- keep `heardTests` small and hosted, with stable boot/configuration checks and experimental hosted perf
- keep `heardUITests` focused on simulator-driven interaction regressions
- keep a first-class stable lane and experimental lane
- keep `.xcresult` summaries as the default diagnostics interface for both humans and agents

Current framework split:

- Swift Testing for non-UI tests where Xcode supports it cleanly
- XCTest for UI tests
- XCTest for performance tests using `measure`

Current Xcode-native split:

- `VoiceCore` scheme for module logic and perf
- `heard-stable` for default hosted and stable UI work
- `heard-experimental` for gesture and hosted perf work

If this file and the playbook diverge, update the playbook and trim this file further rather than duplicating more operational detail here.
