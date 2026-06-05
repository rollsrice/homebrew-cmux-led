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

    func testIsSpinnerBusyDetectsBrailleOnly() {
        XCTAssertTrue(CmuxClient.isSpinnerBusy("⠂ Rename project"))
        XCTAssertTrue(CmuxClient.isSpinnerBusy("⠇ working"))
        // ✳ (U+2733) is a sticky task label, NOT a live spinner.
        XCTAssertFalse(CmuxClient.isSpinnerBusy("✳ Understand todo"))
        XCTAssertFalse(CmuxClient.isSpinnerBusy("helper"))
        XCTAssertFalse(CmuxClient.isSpinnerBusy(""))
    }

    // A workspace is busy when ANY of its surfaces shows a braille spinner.
    // Named workspaces keep their name as the workspace title (no glyph), so the
    // busy state must come from the surfaces, not the workspace title.
    func testParsesBusyWorkspaceRefsFromTree() {
        let tree = """
        window window:1 [current] ◀ active
        ├── workspace workspace:11 "helper"
        │   └── pane pane:11 [focused]
        │       └── surface surface:20 [terminal] "✳ Prune finished branches" [selected]
        ├── workspace workspace:17 "shika"
        │   └── pane pane:22 [focused]
        │       └── surface surface:34 [terminal] "⠂ Evaluate alternatives to Shika" [selected]
        ├── workspace workspace:24 "claude-wrapped"
        │   ├── pane pane:30
        │   │   └── surface surface:48 [terminal] "✳ Evaluate safety" [selected]
        │   └── pane pane:37 [focused]
        │       └── surface surface:57 [filepreview] "wrapped.py"
        ├── workspace workspace:14 "⠂ Rename project to cmux-led"
        │   └── pane pane:14 [focused]
        │       └── surface surface:25 [terminal] "⠂ Rename project to cmux-led" [selected] ◀ here
        └── workspace workspace:12 "language-switch" [selected] ◀ active
            └── pane pane:12 [focused] ◀ active
                └── surface surface:22 [terminal] "~/o/.w/language-switch" [selected] ◀ active
        """
        let busy = CmuxClient.parseBusyWorkspaceRefs(tree)
        // shika: named workspace, plain title, but braille surface → busy.
        // workspace:14: unnamed, braille title + surface → busy.
        XCTAssertEqual(busy, ["workspace:17", "workspace:14"])
    }
}
