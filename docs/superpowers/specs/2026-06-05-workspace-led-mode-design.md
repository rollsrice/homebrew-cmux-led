# Workspace LED mode + vertical pill — design

**Date:** 2026-06-05

## Problem

cmux-led currently shows one LED per **surface** (pane) in the *current* workspace,
laid out as a horizontal pill. There is no way to see activity **across
workspaces** at a glance. Since cmux stacks workspaces vertically, a vertical
pill better matches that mental model.

## Goal

Add a user-selectable **LED mode**:

- **Surface mode** (existing): one LED per surface in the current workspace,
  horizontal pill, trailing aggregate emoji. Click focuses the surface.
- **Workspace mode** (new): one LED per workspace, vertical pill, no aggregate
  emoji. Click selects the workspace.

The mode is a single setting that also picks the orientation. It is exposed in
the status-bar menu and persisted across launches. **Default: Workspace mode.**

## Non-goals

- No independent orientation toggle (mode determines orientation).
- No aggregate pattern emoji in workspace mode.
- No multi-window support beyond what cmux's default-window CLI behavior gives.

## Data source

`cmux workspace list` (alias `list-workspaces`) emits the **same line format**
as `list-pane-surfaces`:

```
  workspace:14  ⠐ Rename project to cmux-led
* workspace:13  ✳ Understand plugin marketplace todo  [selected]
  workspace:4   ⠐ Visualize multiple Android emulators on Mac
```

- Leading `*` = selected.
- Ref token has a `workspace:` prefix (surfaces use `surface:`).
- Busy detection is identical: a leading braille spinner char (U+2800–U+28FF)
  in the title means busy. cmux already rolls up pane activity into the
  workspace title spinner, so no per-pane aggregation is needed in cmux-led.

Selecting a workspace: `cmux select-workspace --workspace <ref>`, then activate
the cmux app — mirroring the existing `focusSurface` behavior.

## Components

### `LEDMode` (new)

```swift
enum LEDMode: String { case surfaces, workspaces }
```

- Persisted in `UserDefaults` under key `"ledMode"`.
- Default `.workspaces` when no stored value.

### `CmuxClient`

- Refactor `parseSurfaceLines(_:)` into a generic
  `parseRefLines(_:prefix:)` that keeps a ref only when its token starts with
  the given prefix. `listSurfaces` calls it with `"surface:"`.
- Add `listWorkspaces() -> [Surface]` calling `workspace list` and
  `parseRefLines(_, prefix: "workspace:")`. (`Surface` is reused as a generic
  ref/title/selected row; it already fits. No rename needed for this change.)
- Add `selectWorkspace(ref:)` mirroring `focusSurface`: runs
  `select-workspace --workspace <ref>` on a background queue, then activates the
  cmux app on the main queue.

### `CmuxMonitor`

- Add `@Published var mode: LEDMode`, initialized from `UserDefaults`. A
  `didSet` (or explicit setter) persists the value and triggers an immediate
  `refreshSnapshot()` on the monitor queue.
- `refreshSnapshot()` branches on `mode`:
  - `.surfaces`: current behavior (resolve current workspace, list its
    surfaces).
  - `.workspaces`: `CmuxClient.listWorkspaces()`.
  Both store into `lastRows` (renamed from `lastSurfaces` for clarity) and call
  `publishPanels()` unchanged.
- `select(index:)` (renamed from `selectSurface(index:)`) dispatches by mode:
  `.surfaces` → `focusSurface`, `.workspaces` → `selectWorkspace`.

### `ContentView`

- `ContentView` reads `monitor.mode` (already an `@ObservedObject`) and maps it
  to orientation internally — no separate orientation parameter. `.surfaces` →
  horizontal, `.workspaces` → vertical.
- Horizontal: existing `HStack` with trailing `PatternEmoji` + `Spacer`.
- Vertical: `VStack` of `LEDDot`s, **no** `PatternEmoji`, trailing `Spacer`.
- `LEDDot` is unchanged (same 22pt hit target, focus ring, tooltip). The tooltip
  text already adapts to title; for workspaces the title is the workspace name.

### `AppDelegate`

- Status-bar menu: add a radio pair after a separator —
  **LEDs: Surfaces** and **LEDs: Workspaces**. Checkmark reflects
  `monitor.mode`. Selecting one sets `monitor.mode`.
- Subscribe to `monitor.$mode`: on change, update menu checkmarks, swap the
  `ContentView` orientation, and re-run the resize for the current count.
- `resizeWindow(forCount:axis:)`:
  - Horizontal (surfaces): width grows with count + trailing slot + emoji-less
    padding (current formula, minus the already-removed emoji reserve); height
    fixed 56. Anchor keeps top edge fixed (existing behavior).
  - Vertical (workspaces): height grows with count + one trailing LED slot;
    width fixed to a single-LED column. Anchor **top-left** so the pill grows
    downward as workspaces are added.
  - Empty/zero-count: keep a stable minimum for the status text.

## Data flow

```
cmux CLI ──(events + 0.5s timer)──▶ CmuxMonitor.refreshSnapshot()
                                       │  branch on mode
                                       ▼
                                   [PanelState]  ──▶ ContentView (H or V)
menu radio ──▶ monitor.mode (persisted) ──▶ resnapshot + orientation swap + resize
LEDDot tap ──▶ monitor.select(index:) ──▶ focusSurface | selectWorkspace
```

## Error handling

- `workspace list` failure (non-zero exit / timeout): return `[]`, same as
  `listSurfaces` today → empty pill / status text. No crash.
- Socket blocked: existing ping-gated path in `refreshSnapshot()` is unchanged
  and covers both modes.
- Unknown/garbled lines: `parseRefLines` skips rows whose ref lacks the expected
  prefix (existing guard behavior).

## Testing

- **Unit:** `parseRefLines` against real `workspace list` and
  `list-pane-surfaces` fixtures — selected flag, busy spinner, titles with
  `[selected]` suffix, blank-title rows. (Surfaces fixtures must still pass after
  the refactor — guards against regression.)
- **Manual / smoke:** build the `.app`, install, and visually confirm:
  1. Default launch → vertical pill listing workspaces; busy ones red.
  2. Switch to Surfaces via menu → pill turns horizontal, shows current
     workspace's panes, emoji returns.
  3. Click a workspace LED → that workspace is selected and cmux activates.
  4. Mode persists across relaunch.
  Capture a screenshot of the running overlay in each orientation.

## Risks / open notes

- `select-workspace` targets the default window. Multi-window users may see it
  act on the wrong window; acceptable for this iteration (matches current
  surface behavior, which is also default-window scoped).
- Vertical pill with many workspaces could grow tall. Out of scope to cap for
  now; revisit if it becomes a problem.
