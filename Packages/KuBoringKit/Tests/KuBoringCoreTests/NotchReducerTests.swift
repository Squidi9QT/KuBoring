import XCTest
@testable import KuBoringCore

final class NotchReducerTests: XCTestCase {
    private func run(_ state: NotchState, _ event: NotchEvent, hover: Bool = true,
                     dropTab: String? = "shelf") -> (NotchState, [NotchEffect]) {
        var s = state
        let effects = NotchReducer.reduce(&s, event, openOnHover: hover, dropTab: dropTab)
        return (s, effects)
    }

    func testPointerEnteredFromClosedPeeks() {
        let (s, e) = run(NotchState(), .pointerEntered)
        XCTAssertEqual(s.phase, .peeking)
        XCTAssertEqual(e, [.scheduleOpen])
    }

    func testPointerEnteredIgnoredWithoutOpenOnHover() {
        let (s, e) = run(NotchState(), .pointerEntered, hover: false)
        XCTAssertEqual(s.phase, .closed)
        XCTAssertTrue(e.isEmpty)
    }

    func testOpenDelayOpensPeeking() {
        let (s, _) = run(NotchState(phase: .peeking), .openDelayElapsed)
        XCTAssertEqual(s.phase, .open)
    }

    func testOpenDelayIgnoredWhenClosed() {
        let (s, _) = run(NotchState(), .openDelayElapsed)
        XCTAssertEqual(s.phase, .closed)
    }

    func testPeekingExitCloses() {
        let (s, e) = run(NotchState(phase: .peeking), .pointerExited)
        XCTAssertEqual(s.phase, .closed)
        XCTAssertEqual(e, [.cancelTimers])
    }

    func testOpenExitSchedulesClose() {
        let (s, e) = run(NotchState(phase: .open), .pointerExited)
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(e, [.scheduleClose])
    }

    func testHoldOpenBlocksCloseOnExit() {
        let (s, e) = run(NotchState(phase: .open, holdOpen: ["ai.typing"]), .pointerExited)
        XCTAssertEqual(s.phase, .open)
        XCTAssertTrue(e.isEmpty)
    }

    func testHoldOpenDoesNotBlockClickedOutside() {
        let (s, _) = run(NotchState(phase: .open, holdOpen: ["ai.typing"]), .clickedOutside)
        XCTAssertEqual(s.phase, .closed)
    }

    func testCloseDelayClosesOpen() {
        let (s, _) = run(NotchState(phase: .open), .closeDelayElapsed)
        XCTAssertEqual(s.phase, .closed)
    }

    func testCloseDelayRespectsLateHold() {
        let (s, _) = run(NotchState(phase: .open, holdOpen: ["x"]), .closeDelayElapsed)
        XCTAssertEqual(s.phase, .open)
    }

    func testPointerReturnCancelsTimers() {
        let (s, e) = run(NotchState(phase: .open), .pointerEntered)
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(e, [.cancelTimers])
    }

    func testClickOpensFromClosedAndPeeking() {
        XCTAssertEqual(run(NotchState(), .clicked).0.phase, .open)
        XCTAssertEqual(run(NotchState(phase: .peeking), .clicked).0.phase, .open)
    }

    func testClickedOutsideIgnoredWhenClosed() {
        XCTAssertEqual(run(NotchState(), .clickedOutside).0.phase, .closed)
    }

    func testDragEnteredFromClosedSelectsDropTab() {
        let (s, _) = run(NotchState(selectedTab: "music"), .dragEntered)
        XCTAssertEqual(s.phase, .dragging)
        XCTAssertEqual(s.selectedTab, "shelf")
        XCTAssertTrue(s.openedByDrag)
    }

    func testDragWhileOpenKeepsTab() {
        let (s, _) = run(NotchState(phase: .open, selectedTab: "music"), .dragEntered)
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.selectedTab, "music")
        XCTAssertFalse(s.openedByDrag)
    }

    func testDragExitedClosesDragging() {
        let (s, _) = run(NotchState(phase: .dragging, selectedTab: "shelf", openedByDrag: true), .dragExited)
        XCTAssertEqual(s.phase, .closed)
        XCTAssertFalse(s.openedByDrag)
    }

    func testDragExitedIgnoredWhenOpen() {
        let (s, _) = run(NotchState(phase: .open, selectedTab: "music"), .dragExited)
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.selectedTab, "music")
    }

    func testDroppedOpensOnDropTab() {
        let (s, _) = run(NotchState(phase: .dragging, openedByDrag: true), .dropped)
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.selectedTab, "shelf")
    }

    func testRequestOpenWithTab() {
        let (s, _) = run(NotchState(), .requestOpen(tab: "timer"))
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.selectedTab, "timer")
    }

    func testRequestOpenWithoutTabKeepsSelection() {
        let (s, _) = run(NotchState(selectedTab: "music"), .requestOpen(tab: nil))
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.selectedTab, "music")
    }

    func testRequestCloseIgnoresHold() {
        let (s, _) = run(NotchState(phase: .open, holdOpen: ["x"]), .requestClose)
        XCTAssertEqual(s.phase, .closed)
    }

    func testSelectTab() {
        let (s, _) = run(NotchState(phase: .open, selectedTab: "music"), .selectTab("ai"))
        XCTAssertEqual(s.selectedTab, "ai")
    }

    func testDragWhileOpenNeverEntersDraggingEvenWithHold() {
        let (s, _) = run(NotchState(phase: .open, selectedTab: "ai", holdOpen: ["tab.stayOpen"]),
                         .dragEntered)
        XCTAssertEqual(s.phase, .open)
        XCTAssertEqual(s.selectedTab, "ai")
        XCTAssertFalse(s.openedByDrag)
    }

    func testStayOpenHoldBlocksPointerExitButNotClickOutside() {
        let st = NotchState(phase: .open, selectedTab: "ai", holdOpen: ["tab.stayOpen"])
        XCTAssertTrue(run(st, .pointerExited).1.isEmpty)
        XCTAssertEqual(run(st, .clickedOutside).0.phase, .closed)
    }
}
