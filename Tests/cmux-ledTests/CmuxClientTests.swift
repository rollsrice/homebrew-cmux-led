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
