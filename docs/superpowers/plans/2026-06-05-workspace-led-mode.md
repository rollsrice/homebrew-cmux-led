# Workspace LED Mode + Vertical Pill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted, menu-selectable LED mode — surfaces (horizontal pill, existing) or workspaces (new vertical pill) — that monitors and switches cmux focus accordingly.

**Architecture:** Generalize the existing surface-list parser/plumbing to also handle `cmux workspace list` (identical line format, `workspace:` prefix). `CmuxMonitor` gains a published `mode` that branches snapshotting and click-dispatch. `ContentView` maps mode → axis (HStack+emoji vs VStack). `AppDelegate` adds a menu radio pair and an axis-aware window resize.

**Tech Stack:** Swift 5.9, SwiftPM, SwiftUI + AppKit, XCTest, macOS 13+.

**Spec:** `/Users/ryan/cmux-led/docs/superpowers/specs/2026-06-05-workspace-led-mode-design.md`

---

## Pre-flight

- [ ] **Create feature branch** (repo is on `main`)

```bash
cd /Users/ryan/cmux-led
git checkout -b workspace-led-mode
```

---

## File Structure

- `Package.swift` — add an XCTest test target.
- `Sources/cmux-led/CmuxClient.swift` — generalize parser; add workspace list + select.
- `Sources/cmux-led/LEDMode.swift` — **new** — mode enum + UserDefaults persistence.
- `Sources/cmux-led/CmuxMonitor.swift` — mode-aware snapshot + click dispatch.
- `Sources/cmux-led/ContentView.swift` — orientation from mode.
- `Sources/cmux-led/AppDelegate.swift` — menu radio + axis-aware resize.
- `Tests/cmux-ledTests/CmuxClientTests.swift` — **new** — parser unit tests.
- `Tests/cmux-ledTests/LEDModeTests.swift` — **new** — persistence unit tests.

**Test scope note:** Only pure logic is unit-tested — `parseRefLines` (parsing) and `LEDMode` (persistence). View layout, window resize, menu wiring, and CLI-hitting methods (`listWorkspaces`, `selectWorkspace`, snapshot branching) are verified in the Task 8 smoke test with screenshots, not unit tests. Adding dependency injection just to mock the cmux binary is out of scope (YAGNI).

---

## Task 1: Add test target + failing parser tests

**Files:**
- Modify: `Package.swift`
- Create: `Tests/cmux-ledTests/CmuxClientTests.swift`

The target `cmux-led` builds module `cmux_led` (hyphen → underscore). Tests use `@testable import cmux_led`.

- [ ] **Step 1: Add the test target to Package.swift**

Replace the whole `targets:` array:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "cmux-led",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "cmux-led",
            path: "Sources/cmux-led"
        ),
        .testTarget(
            name: "cmux-ledTests",
            dependencies: ["cmux-led"],
            path: "Tests/cmux-ledTests"
        )
    ]
)
```

- [ ] **Step 2: Write failing tests for the generalized parser**

These reference `CmuxClient.parseRefLines(_:prefix:)`, which does not exist yet (currently it's `parseSurfaceLines`). The surface cases lock in existing behavior so the Task 2 refactor can't regress.

```swift
import XCTest
@testable import cmux_led

final class CmuxClientTests: XCTestCase {
    func testParsesSurfaceLines() {
        let text = """
          surface:1  hello
        * surface:2  ⠐ working title  [selected]
        """
        let rows = CmuxClient.parseRefLines(text, prefix: "surface:")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].ref, "surface:1")
        XCTAssertEqual(rows[0].title, "hello")
        XCTAssertFalse(rows[0].selected)
        XCTAssertEqual(rows[1].ref, "surface:2")
        XCTAssertEqual(rows[1].title, "⠐ working title")
        XCTAssertTrue(rows[1].selected)
    }

    func testParsesWorkspaceLines() {
        let text = """
          workspace:14  ⠐ Rename project to cmux-led
        * workspace:13  ✳ Understand plugin marketplace todo  [selected]
          workspace:4  Visualize emulators
        """
        let rows = CmuxClient.parseRefLines(text, prefix: "workspace:")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].ref, "workspace:14")
        XCTAssertEqual(rows[0].title, "⠐ Rename project to cmux-led")
        XCTAssertTrue(rows[1].selected)
        XCTAssertEqual(rows[1].ref, "workspace:13")
        XCTAssertEqual(rows[2].ref, "workspace:4")
        XCTAssertFalse(rows[2].selected)
    }

    func testSkipsRowsWithWrongPrefix() {
        let text = """
          surface:1  keep me
          window:9  drop me
        garbage line
        """
        let rows = CmuxClient.parseRefLines(text, prefix: "surface:")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].ref, "surface:1")
    }

    func testParsesRefWithNoTitle() {
        let text = "  workspace:7"
        let rows = CmuxClient.parseRefLines(text, prefix: "workspace:")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].ref, "workspace:7")
        XCTAssertEqual(rows[0].title, "")
    }
}
```

- [ ] **Step 3: Run tests, verify they fail to compile**

Run: `swift test 2>&1 | tail -20`
Expected: build failure — `type 'CmuxClient' has no member 'parseRefLines'`.

- [ ] **Step 4: Commit the test scaffolding**

```bash
git add Package.swift Tests/cmux-ledTests/CmuxClientTests.swift
git commit -m "test: add test target + failing parseRefLines specs"
```

---

## Task 2: Generalize the parser

**Files:**
- Modify: `Sources/cmux-led/CmuxClient.swift` (replace `parseSurfaceLines`, update `listSurfaces`)

- [ ] **Step 1: Replace `parseSurfaceLines` with `parseRefLines`**

In `CmuxClient.swift`, replace the entire `parseSurfaceLines` function with this generalized version. It is the same logic, but the hard-coded `"surface:"` checks become the `prefix` parameter.

```swift
    static func parseRefLines(_ text: String, prefix: String) -> [Surface] {
        var out: [Surface] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            let selected = line.hasPrefix("*")
            var rest = line
            if line.count >= 2 {
                rest = String(line.dropFirst(2))
            }
            let trimmed = rest.trimmingCharacters(in: .whitespaces)
            guard let spaceIdx = trimmed.firstIndex(of: " ") else {
                if trimmed.hasPrefix(prefix) {
                    out.append(Surface(ref: trimmed, title: "", selected: selected))
                }
                continue
            }
            let ref = String(trimmed[..<spaceIdx])
            guard ref.hasPrefix(prefix) else { continue }
            var title = String(trimmed[trimmed.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
            if title.hasSuffix("[selected]") {
                title = String(title.dropLast("[selected]".count)).trimmingCharacters(in: .whitespaces)
            }
            out.append(Surface(ref: ref, title: title, selected: selected))
        }
        return out
    }
```

- [ ] **Step 2: Point `listSurfaces` at the generalized parser**

Replace the body of `listSurfaces`:

```swift
    static func listSurfaces(workspaceRef: String) -> [Surface] {
        let r = runText(["list-pane-surfaces", "--workspace", workspaceRef], timeout: 1.5)
        guard r.code == 0 else { return [] }
        return parseRefLines(r.out, prefix: "surface:")
    }
```

- [ ] **Step 3: Run tests, verify pass**

Run: `swift test 2>&1 | tail -20`
Expected: all 4 `CmuxClientTests` pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/cmux-led/CmuxClient.swift
git commit -m "refactor: generalize surface parser to parseRefLines(_:prefix:)"
```

---

## Task 3: Add workspace list + select to CmuxClient

**Files:**
- Modify: `Sources/cmux-led/CmuxClient.swift` (add two methods)

- [ ] **Step 1: Add `listWorkspaces` and `selectWorkspace`**

Add these inside the `CmuxClient` enum, after `listSurfaces`:

```swift
    static func listWorkspaces() -> [Surface] {
        let r = runText(["workspace", "list"], timeout: 1.5)
        guard r.code == 0 else { return [] }
        return parseRefLines(r.out, prefix: "workspace:")
    }

    static func selectWorkspace(ref: String) {
        DispatchQueue.global().async {
            _ = runText(["select-workspace", "--workspace", ref], timeout: 1.0)
            DispatchQueue.main.async {
                NSRunningApplication
                    .runningApplications(withBundleIdentifier: "com.cmuxterm.app")
                    .first?
                    .activate(options: [.activateAllWindows])
            }
        }
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: `Compiling`/`Build complete`, no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/cmux-led/CmuxClient.swift
git commit -m "feat: add workspace list + select to CmuxClient"
```

---

## Task 4: Add LEDMode enum with persistence

**Files:**
- Create: `Sources/cmux-led/LEDMode.swift`
- Create: `Tests/cmux-ledTests/LEDModeTests.swift`

- [ ] **Step 1: Write failing persistence tests**

```swift
import XCTest
@testable import cmux_led

final class LEDModeTests: XCTestCase {
    private let suiteName = "LEDModeTests.suite"

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }

    func testDefaultsToWorkspacesWhenUnset() {
        let d = freshDefaults()
        XCTAssertEqual(LEDMode.load(from: d), .workspaces)
    }

    func testRoundTripsThroughDefaults() {
        let d = freshDefaults()
        LEDMode.surfaces.save(to: d)
        XCTAssertEqual(LEDMode.load(from: d), .surfaces)
        LEDMode.workspaces.save(to: d)
        XCTAssertEqual(LEDMode.load(from: d), .workspaces)
    }

    func testIgnoresGarbageStoredValue() {
        let d = freshDefaults()
        d.set("nonsense", forKey: "ledMode")
        XCTAssertEqual(LEDMode.load(from: d), .workspaces)
    }
}
```

- [ ] **Step 2: Run tests, verify they fail to compile**

Run: `swift test 2>&1 | tail -20`
Expected: build failure — no type `LEDMode`.

- [ ] **Step 3: Create LEDMode.swift**

```swift
import Foundation

enum LEDMode: String {
    case surfaces
    case workspaces

    static let defaultsKey = "ledMode"

    static func load(from defaults: UserDefaults = .standard) -> LEDMode {
        guard let raw = defaults.string(forKey: defaultsKey),
              let mode = LEDMode(rawValue: raw) else {
            return .workspaces
        }
        return mode
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: LEDMode.defaultsKey)
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `swift test 2>&1 | tail -20`
Expected: all `LEDModeTests` + `CmuxClientTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/cmux-led/LEDMode.swift Tests/cmux-ledTests/LEDModeTests.swift
git commit -m "feat: add LEDMode enum with UserDefaults persistence"
```

---

## Task 5: Make CmuxMonitor mode-aware

**Files:**
- Modify: `Sources/cmux-led/CmuxMonitor.swift`

- [ ] **Step 1: Add a published `mode`, initialized from defaults**

Add after the existing `@Published var connected` line (around line 15):

```swift
    @Published var mode: LEDMode = LEDMode.load() {
        didSet {
            guard oldValue != mode else { return }
            mode.save()
            queue.async { [weak self] in self?.refreshSnapshot() }
        }
    }
```

- [ ] **Step 2: Branch `refreshSnapshot` on mode**

Replace the body of `refreshSnapshot` (currently surface-only) with a mode branch. Note `currentWorkspaceRef` is only resolved/used in surface mode now.

```swift
    private func refreshSnapshot() {
        guard CmuxClient.ping() else {
            DispatchQueue.main.async { [weak self] in
                self?.connected = false
                self?.status = "cmux socket blocked"
            }
            return
        }
        let rows: [Surface]
        switch mode {
        case .surfaces:
            let wsId = CmuxClient.currentWorkspaceRef() ?? currentWorkspaceRef
            currentWorkspaceRef = wsId
            rows = CmuxClient.listSurfaces(workspaceRef: wsId)
        case .workspaces:
            rows = CmuxClient.listWorkspaces()
        }
        lastRows = rows
        publishPanels()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.connected { self.connected = true; self.status = "connected" }
        }
    }
```

- [ ] **Step 3: Rename `lastSurfaces` → `lastRows`**

Rename the stored property declaration (around line 21):

```swift
    private var lastRows: [Surface] = []
```

And update its use in `publishPanels` (the `enumerated()` source):

```swift
    private func publishPanels() {
        let states = lastRows.enumerated().map { (i, s) -> PanelState in
            PanelState(
                id: s.ref,
                index: i,
                title: s.title,
                isBusy: titleSpinnerBusy(s.title),
                isFocused: s.selected
            )
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.panels != states { self.panels = states }
        }
    }
```

- [ ] **Step 4: Replace `selectSurface(index:)` with mode-dispatching `select(index:)`**

```swift
    func select(index: Int) {
        guard index >= 0, index < lastRows.count else { return }
        let ref = lastRows[index].ref
        switch mode {
        case .surfaces:
            CmuxClient.focusSurface(workspaceRef: currentWorkspaceRef, surfaceRef: ref)
        case .workspaces:
            CmuxClient.selectWorkspace(ref: ref)
        }
    }
```

- [ ] **Step 5: Build to verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: build complete. (Will still fail at the AppDelegate call site `selectSurface` — that's fixed in Task 7. If building the whole package errors only on `AppDelegate.swift` referencing `selectSurface`/`resizeWindow`, that is expected; proceed to Task 6–7 before the next full build. Run `swift build --target cmux-led 2>&1 | grep CmuxMonitor` to confirm CmuxMonitor itself has no errors.)

- [ ] **Step 6: Commit**

```bash
git add Sources/cmux-led/CmuxMonitor.swift
git commit -m "feat: make CmuxMonitor mode-aware (surfaces|workspaces)"
```

---

## Task 6: Orientation in ContentView

**Files:**
- Modify: `Sources/cmux-led/ContentView.swift`

- [ ] **Step 1: Replace the `body` layout with a mode-driven branch**

`monitor` is already an `@ObservedObject`, so reading `monitor.mode` re-renders on change. Replace the existing `body` of `ContentView`:

```swift
    var body: some View {
        Group {
            if monitor.panels.isEmpty {
                HStack(spacing: 8) {
                    Text(monitor.status)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 6)
                    Spacer(minLength: 0)
                }
            } else if monitor.mode == .workspaces {
                VStack(spacing: 8) {
                    ForEach(monitor.panels) { p in
                        LEDDot(isBusy: p.isBusy, isFocused: p.isFocused, title: p.title, index: p.index) {
                            onSelect(p.index)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(monitor.panels) { p in
                        LEDDot(isBusy: p.isBusy, isFocused: p.isFocused, title: p.title, index: p.index) {
                            onSelect(p.index)
                        }
                    }
                    PatternEmoji(pattern: BarPattern.from(monitor.panels))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedVisualEffect(cornerRadius: cornerR))
        .overlay(
            RoundedRectangle(cornerRadius: cornerR)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 2)
        .padding(8)
        .contextMenu {
            Toggle("Always on top", isOn: $alwaysOnTop)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }
```

- [ ] **Step 2: Build to verify ContentView compiles**

Run: `swift build 2>&1 | grep -i contentview`
Expected: no ContentView errors (AppDelegate errors from Task 7 still allowed).

- [ ] **Step 3: Commit**

```bash
git add Sources/cmux-led/ContentView.swift
git commit -m "feat: vertical pill (no emoji) for workspace mode"
```

---

## Task 7: Menu radio + axis-aware resize in AppDelegate

**Files:**
- Modify: `Sources/cmux-led/AppDelegate.swift`

- [ ] **Step 1: Replace the panel-count subscription with a relayout that knows the axis**

In `applicationDidFinishLaunching`, replace the existing `monitor.$panels.map { $0.count }...` subscription and the trailing `resizeWindow(forTabCount: 0)` call with:

```swift
        monitor.$panels
            .map { $0.count }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayout() }
            .store(in: &cancellables)

        monitor.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshModeMenu()
                self?.relayout()
            }
            .store(in: &cancellables)

        relayout()
```

- [ ] **Step 2: Replace `resizeWindow(forTabCount:)` with `relayout()` + axis-aware resize**

Replace the entire `resizeWindow(forTabCount:)` method with:

```swift
    private func relayout() {
        let count = monitor.panels.count
        let axis: Axis = monitor.mode == .workspaces ? .vertical : .horizontal
        resizeWindow(forCount: count, axis: axis)
    }

    private func resizeWindow(forCount count: Int, axis: Axis) {
        // Stack axis: N LED slots (22 + 8 spacing) + one trailing empty LED slot + padding.
        // Cross axis: single LED column/row thickness.
        let ledSlot: CGFloat = 30
        let trailingEmpty: CGFloat = 30
        let padding: CGFloat = 40
        let stackExtent = count == 0 ? 200 : CGFloat(count) * ledSlot - 8 + trailingEmpty + padding

        let width: CGFloat
        let height: CGFloat
        if count == 0 {
            // Empty/status text always shows as a small horizontal pill.
            width = 200
            height = 56
        } else if axis == .vertical {
            width = 62           // one LED + horizontal padding
            height = stackExtent
        } else {
            width = stackExtent
            height = 56
        }

        let frame = window.frame
        // Keep the top-left anchored: top edge fixed, grow down; left edge fixed.
        let newOrigin = NSPoint(x: frame.origin.x, y: frame.origin.y + (frame.height - height))
        let newFrame = NSRect(origin: newOrigin, size: NSSize(width: width, height: height))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(newFrame, display: true)
        }
    }
```

`Axis` comes from SwiftUI, already imported in this file.

- [ ] **Step 3: Update the click handler to call `select(index:)`**

In the `ContentView(...)` initializer in `applicationDidFinishLaunching`, change the `onSelect` closure:

```swift
            onSelect: { [weak self] idx in self?.monitor.select(index: idx) }
```

- [ ] **Step 4: Add the mode radio pair to the status-bar menu**

In `installStatusItem()`, after the `pinItem` block and before the `Show window` item, insert the radio pair. Keep references so they can be re-checked.

```swift
        menu.addItem(.separator())
        let surfacesItem = NSMenuItem(title: "LEDs: Surfaces", action: #selector(setSurfacesMode), keyEquivalent: "")
        surfacesItem.target = self
        menu.addItem(surfacesItem)
        let workspacesItem = NSMenuItem(title: "LEDs: Workspaces", action: #selector(setWorkspacesMode), keyEquivalent: "")
        workspacesItem.target = self
        menu.addItem(workspacesItem)
        self.surfacesMenuItem = surfacesItem
        self.workspacesMenuItem = workspacesItem
        refreshModeMenu()
        menu.addItem(.separator())
```

- [ ] **Step 5: Add the menu-item stored properties + actions + refresh**

Add stored properties near the top of `AppDelegate` (after `private var statusItem: NSStatusItem?`):

```swift
    private var surfacesMenuItem: NSMenuItem?
    private var workspacesMenuItem: NSMenuItem?
```

Add these methods to `AppDelegate`:

```swift
    @objc private func setSurfacesMode() { monitor.mode = .surfaces }
    @objc private func setWorkspacesMode() { monitor.mode = .workspaces }

    private func refreshModeMenu() {
        surfacesMenuItem?.state = monitor.mode == .surfaces ? .on : .off
        workspacesMenuItem?.state = monitor.mode == .workspaces ? .on : .off
    }
```

- [ ] **Step 6: Build the whole package**

Run: `swift build 2>&1 | tail -5`
Expected: `Build complete!` — no errors.

- [ ] **Step 7: Run unit tests (regression check)**

Run: `swift test 2>&1 | tail -10`
Expected: all `CmuxClientTests` + `LEDModeTests` pass.

- [ ] **Step 8: Commit**

```bash
git add Sources/cmux-led/AppDelegate.swift
git commit -m "feat: mode menu radio + axis-aware window resize"
```

---

## Task 8: Build app bundle + smoke test with screenshots

**Files:** none (verification only)

- [ ] **Step 1: Build + reinstall the app bundle**

```bash
cd /Users/ryan/cmux-led
rm -rf .build
./build-app.sh 2>&1 | tail -3
pkill -f /Applications/cmux-led.app; sleep 1
rm -rf /Applications/cmux-led.app
cp -R build/cmux-led.app /Applications/
xattr -dr com.apple.quarantine /Applications/cmux-led.app 2>/dev/null
open -a /Applications/cmux-led.app && sleep 1 && pgrep -fl cmux-led
```

Expected: artifact + sha printed, pid printed.

- [ ] **Step 2: Screenshot workspace mode (default)**

Capture the overlay window and Read the PNG into chat.

```bash
screencapture -x /tmp/cmux-led-workspaces.png
```

Verify: vertical pill, one LED per workspace, busy workspaces red, selected ringed. Read `/tmp/cmux-led-workspaces.png`.

- [ ] **Step 3: Switch to Surfaces via the menu, screenshot**

Click the status-bar "●" → "LEDs: Surfaces". Then:

```bash
screencapture -x /tmp/cmux-led-surfaces.png
```

Verify: pill turns horizontal, shows current workspace's panes, trailing emoji returns when busy/mixed. Read `/tmp/cmux-led-surfaces.png`.

- [ ] **Step 4: Verify click-to-focus**

In workspace mode, click a non-selected workspace LED. Confirm cmux switches to that workspace and activates. (Spot-check, no screenshot required.)

- [ ] **Step 5: Verify persistence across relaunch**

```bash
pkill -f /Applications/cmux-led.app; sleep 1
open -a /Applications/cmux-led.app && sleep 1
screencapture -x /tmp/cmux-led-persist.png
```

Verify: the mode chosen in Step 3 (surfaces) is restored on relaunch. Read `/tmp/cmux-led-persist.png`.

- [ ] **Step 6: Code review**

Spawn a Code Reviewer agent on the full branch diff (`git diff main...HEAD`) before reporting done.

---

## Self-Review (completed during planning)

- **Spec coverage:** mode enum+persistence (Task 4), workspace data source + select (Task 3), parser generalization (Task 1–2), monitor branching + dispatch (Task 5), vertical pill no-emoji (Task 6), menu radio + vertical resize + default Workspace (Task 4/7), error handling preserved (`guard r.code == 0 → []`, ping gate untouched — Task 2/3/5), unit + smoke testing (Task 1/4/8). All spec sections mapped.
- **Type consistency:** `parseRefLines(_:prefix:)`, `listWorkspaces()`, `selectWorkspace(ref:)`, `LEDMode.load/save`, `select(index:)`, `lastRows`, `relayout()`, `resizeWindow(forCount:axis:)`, `refreshModeMenu()` used consistently across tasks.
- **Known cross-task build gap:** AppDelegate references old `selectSurface`/`resizeWindow(forTabCount:)` until Task 7. Flagged in Task 5 Step 5 — full `swift build` only expected green after Task 7.
