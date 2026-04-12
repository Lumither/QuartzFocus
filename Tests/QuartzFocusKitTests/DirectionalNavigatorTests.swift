import ApplicationServices
import XCTest

@testable import QuartzFocusKit

final class DirectionalNavigatorTests: XCTestCase {
    private let navigator = DirectionalNavigator()

    func testChoosesNearestCardinalWindow() {
        let current = window(id: 1, x: 300, y: 300, width: 200, height: 200)
        let left = window(id: 2, x: 40, y: 320, width: 180, height: 160)
        let right = window(id: 3, x: 620, y: 320, width: 180, height: 160)
        let down = window(id: 4, x: 320, y: 620, width: 160, height: 180)
        let up = window(id: 5, x: 320, y: 40, width: 160, height: 180)

        let candidates = [left, right, down, up]

        XCTAssertEqual(
            navigator.target(from: current, candidates: candidates, direction: .left)?.windowID,
            left.windowID)
        XCTAssertEqual(
            navigator.target(from: current, candidates: candidates, direction: .right)?.windowID,
            right.windowID)
        XCTAssertEqual(
            navigator.target(from: current, candidates: candidates, direction: .down)?.windowID,
            down.windowID)
        XCTAssertEqual(
            navigator.target(from: current, candidates: candidates, direction: .up)?.windowID, up.windowID
        )
    }

    func testAllowsCrossMonitorCandidate() {
        let current = window(id: 1, x: 600, y: 200, width: 220, height: 180, screenID: 1)
        let crossMonitorRight = window(id: 2, x: 1700, y: 220, width: 240, height: 200, screenID: 2)
        let left = window(id: 3, x: 120, y: 220, width: 220, height: 200, screenID: 1)

        let candidates = [crossMonitorRight, left]

        XCTAssertEqual(
            navigator.target(from: current, candidates: candidates, direction: .right)?.windowID,
            crossMonitorRight.windowID)
    }

    func testPrefersCloserSpatialCandidateInDirection() {
        let current = window(id: 1, x: 300, y: 300, width: 200, height: 200)
        let farLeft = window(id: 2, x: -220, y: 320, width: 180, height: 160)
        let closerDiagonalLeft = window(id: 3, x: 120, y: 470, width: 180, height: 180)

        let candidates = [farLeft, closerDiagonalLeft]

        XCTAssertEqual(
            navigator.target(from: current, candidates: candidates, direction: .left)?.windowID,
            closerDiagonalLeft.windowID)
    }

    func testReturnsNilWhenNoCandidateExistsInDirection() {
        let current = window(id: 1, x: 300, y: 300, width: 200, height: 200)
        let left = window(id: 2, x: 40, y: 320, width: 180, height: 160)

        XCTAssertNil(navigator.target(from: current, candidates: [left], direction: .right))
        XCTAssertNil(navigator.target(from: current, candidates: [left], direction: .up))
    }

    private func window(
        id: CGWindowID,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        screenID: CGDirectDisplayID? = nil
    ) -> WindowCandidate {
        WindowCandidate(
            pid: 1,
            windowID: id,
            frame: CGRect(x: x, y: y, width: width, height: height),
            axWindow: AXUIElementCreateSystemWide(),
            screenID: screenID
        )
    }
}
