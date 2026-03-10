# Repo Structure Roadmap

## Summary

The repo now has one real reusable subsystem: `VoiceCore`.

That is the template to follow going forward:

- reusable subsystem code belongs in `Modules/`
- app shell and integration glue stay in `app/`
- app-host tests stay small
- subsystem logic tests live with the subsystem

This document explains the intended repo shape now and the cleanup steps that should happen next without introducing churn-heavy moves too early.

## Current Top-Level Layout

### `app/`

The app shell and integration layer.

This currently contains:

- models and persistence wiring
- UI and feature views
- app lifecycle and warmup
- Gemini integration glue
- thin app-side integration with module-owned subsystems

### `Modules/`

Reusable internal modules.

Current example:

- `Modules/VoiceCore`

Expected module shape:

- `Modules/<Subsystem>/Sources/<Module>/`
- `Modules/<Subsystem>/Tests/<Module>Tests/`

### `docs/`

Engineering documentation, rebuild notes, playbooks, and architecture guidance.

### `design/`

Mockups and design artifacts.

### `heardTests/`

Smoke-only app-host tests.

### `refs/`

Temporary reference material collected during architecture and implementation work.

## Rules of Ownership

### Reusable subsystem code

Belongs in:

- `Modules/<Subsystem>/Sources/<Module>/`

Examples:

- audio/session/call coordination
- future shared transports
- future reusable infrastructure that is not app-shell-specific

### Subsystem tests

Belong in:

- `Modules/<Subsystem>/Tests/<Module>Tests/`

These should own the real logic coverage.

### App shell and integration glue

Stay in:

- `app/`

This includes:

- feature UI
- persistence wiring
- app lifecycle
- Gemini integration glue
- module composition

### `heardTests`

Stay smoke-only.

They should prove:

- the app test host launches
- test mode behaves correctly
- minimal integration still works

They should not become the primary place for subsystem logic.

## Why This Shape

- It creates real module boundaries instead of file-level conventions.
- It makes future SwiftPM extraction much easier.
- It reduces app-host test fragility.
- It keeps reusable code separate from app-shell code.
- It gives a clear default for where new tests should go.

## Current Example: `VoiceCore`

`VoiceCore` is the first concrete subsystem following this pattern.

It demonstrates:

- module-owned sources
- module-owned logic tests
- app-side integration through imports and thin coordination

This should be treated as the reference example for future internal modules.

## What Gets Extracted Next

### 1. Deeper `VoiceCore` work

The next meaningful technical step inside `VoiceCore` is not folder churn. It is behavior hardening:

- explicit call lifecycle state machine
- explicit route lifecycle state machine
- clearer structured eventing for capture, playback, and transport boundaries

### 2. Possible Gemini transport modularization

If the Gemini integration grows more complex or needs reuse beyond the current app shell, a dedicated transport-oriented module may make sense.

That is not a current commitment. It is a future candidate.

### 3. Possible terminal/tooling module

Only extract a terminal/tooling module if it becomes real reusable product infrastructure, not just local scripts or experiments.

## What Is Deferred

These are intentionally not part of the current cleanup pass:

- a full `app/App`, `app/Features`, `app/Shared` split
- wholesale voice/audio replacement
- broad top-level churn
- moving everything possible into modules before there is a second real subsystem

## `refs/` Policy

`refs/` is scratch/reference material only.

Rules:

- it is not production code
- it should not appear in architecture ownership rules
- project files and runtime docs should not depend on it
- it can remain temporarily useful during active exploration
- it should eventually be removed once it stops paying for itself

In practice:

- treat `refs/` as disposable learning material
- do not build new architecture around it

## Migration Triggers

Do the next round of structural cleanup only when one of these becomes true:

- a second reusable subsystem is extracted into `Modules/`
- `app/` becomes crowded enough that ownership is unclear
- multiple module targets need shared conventions or shared infrastructure

At that point, consider a measured split of `app/` into:

- `app/App/`
- `app/Features/`
- `app/Shared/`

That should happen incrementally, not as a giant one-shot churn.

## Recommended Near-Term Cleanup Order

1. Keep `Modules/` as the home for reusable subsystems.
2. Keep `app/` as the app shell and UI/integration layer.
3. Keep `heardTests` smoke-only.
4. Add and maintain clear testing and architecture docs.
5. Extract the next real subsystem before attempting the larger `app/` split.

## Long-Term Direction

The long-term direction is a repo where:

- modules own reusable logic and their own tests
- the app layer composes modules instead of absorbing their internals
- hosted app tests stay lean
- manual device validation is documented where platform behavior still limits automation

That is the direction to continue, but the current repo is not yet at the point where a churn-heavy reorganization would be worth the cost.
