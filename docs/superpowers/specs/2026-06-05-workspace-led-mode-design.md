# Workspace LED mode + vertical pill — design

**Date:** 2026-06-05

## Goal

Add a user-selectable **LED mode** (status-bar menu, persisted, default **Workspace**):

- **Surface** (existing): LED per surface in current workspace. Horizontal pill, trailing emoji. Click focuses surface.
- **Workspace** (new): LED per workspace. Vertical pill, no emoji. Click selects workspace.

Mode also picks orientation. No separate orientation toggle.

## Data source

`cmux workspace list` emits the same line format as `list-pane-surfaces`
(`* ref  <spinner> title [selected]`), just a `workspace:` prefix. Busy =
leading braille spinner (U+2800–U+28FF) — cmux already rolls pane activity into
the workspace title spinner. Select: `cmux select-workspace --workspace <ref>`.

## Changes

- **`LEDMode`** enum `{ surfaces, workspaces }`. Persisted in `UserDefaults` key `"ledMode"`, default `.workspaces`.
- **`CmuxClient`**: generalize `parseSurfaceLines` → `parseRefLines(_:prefix:)`. Add `listWorkspaces()` (`workspace list`, prefix `workspace:`) and `selectWorkspace(ref:)` (mirrors `focusSurface`).
- **`CmuxMonitor`**: add `@Published var mode` (from UserDefaults; setter persists + resnapshots). `refreshSnapshot()` branches by mode; both publish `[PanelState]`. Rename `selectSurface(index:)` → `select(index:)`, dispatching `focusSurface` | `selectWorkspace`.
- **`ContentView`**: read `monitor.mode`, map to orientation. `.surfaces` → `HStack` + emoji (current). `.workspaces` → `VStack`, no emoji. `LEDDot` unchanged.
- **`AppDelegate`**: menu radio pair **LEDs: Surfaces** / **LEDs: Workspaces** (checkmark = active). Subscribe `monitor.$mode` → swap orientation + resize. `resizeWindow(forCount:axis:)`: horizontal grows width (current formula); vertical grows height, fixed single-LED width, anchored top-left (grows down). Keep stable minimum for empty state.

## Error handling

`workspace list` failure → `[]` (same as `listSurfaces`). Socket-blocked ping
gate unchanged, covers both modes. `parseRefLines` skips rows missing the prefix.

## Testing

- **Unit:** `parseRefLines` against `workspace list` + `list-pane-surfaces` fixtures (selected flag, busy spinner, `[selected]` suffix, blank titles). Surface fixtures must still pass after refactor.
- **Smoke:** build + install, confirm: default → vertical workspace pill (busy red); switch to Surfaces → horizontal + emoji; click workspace LED selects it + activates cmux; mode persists across relaunch. Screenshot each orientation.

## Notes

`select-workspace` targets default window (matches current surface behavior).
Tall pill with many workspaces — not capped this iteration.
