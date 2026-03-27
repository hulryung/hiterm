import XCTest
@testable import hiterm

final class SplitNodeTests: XCTestCase {

    // MARK: - Tab Management

    func testTabIndexBoundsAfterClose() {
        // Simulate: 3 tabs, close middle one, verify indices are valid.
        var tabs = ["A", "B", "C"]
        let closeIndex = 1
        tabs.remove(at: closeIndex)

        XCTAssertEqual(tabs.count, 2)
        let newIndex = min(closeIndex, tabs.count - 1)
        XCTAssertEqual(newIndex, 1)
        XCTAssertEqual(tabs[newIndex], "C")
    }

    func testTabIndexBoundsAfterCloseLast() {
        var tabs = ["A", "B", "C"]
        let closeIndex = 2
        tabs.remove(at: closeIndex)

        let newIndex = min(closeIndex, tabs.count - 1)
        XCTAssertEqual(newIndex, 1)
        XCTAssertEqual(tabs[newIndex], "B")
    }

    func testTabIndexBoundsAfterCloseFirst() {
        var tabs = ["A", "B", "C"]
        let closeIndex = 0
        tabs.remove(at: closeIndex)

        let newIndex = min(closeIndex, tabs.count - 1)
        XCTAssertEqual(newIndex, 0)
        XCTAssertEqual(tabs[newIndex], "B")
    }

    func testTabIndexBoundsAfterCloseOnlyRemaining() {
        var tabs = ["A"]
        tabs.remove(at: 0)
        XCTAssertTrue(tabs.isEmpty)
    }

    // MARK: - Swipe Progress Calculation

    func testKeyAnimProgressCalculation() {
        // Simulate: baseIndex=0, target=1, width=900
        let baseIndex = 0
        let targetIndex = 1
        let width: CGFloat = 900

        let targetX = CGFloat(baseIndex - targetIndex) * width  // -900
        var currentX: CGFloat = 0

        // Simulate animation frames.
        for _ in 0..<5 {
            let distance = targetX - currentX
            currentX += distance * 0.2
        }

        let progress = targetX != 0 ? abs(currentX / targetX) : 1.0
        XCTAssertGreaterThan(progress, 0.3, "After 5 frames, should be past 30%")
        XCTAssertLessThan(progress, 1.0, "Should not have reached target yet")
    }

    func testKeyAnimProgressNeverExceedsOne() {
        let targetX: CGFloat = -900
        var currentX: CGFloat = 0

        for _ in 0..<100 {
            let distance = targetX - currentX
            if abs(distance) < 1.0 {
                currentX = targetX
                break
            }
            currentX += distance * 0.2
        }

        let progress = abs(currentX / targetX)
        XCTAssertLessThanOrEqual(progress, 1.0)
    }

    // MARK: - Direction Lock

    func testDirectionLockVertical() {
        var accumX: CGFloat = 0
        var accumY: CGFloat = 0
        let slopeThreshold: CGFloat = 0.4
        let directionThreshold: CGFloat = 10

        // Simulate vertical movement.
        accumX += 2
        accumY += 12

        XCTAssertTrue(accumX + accumY >= directionThreshold)
        let isVertical = accumY > slopeThreshold * (accumX + accumY)
        XCTAssertTrue(isVertical, "Should detect vertical direction")
    }

    func testDirectionLockHorizontal() {
        var accumX: CGFloat = 0
        var accumY: CGFloat = 0
        let slopeThreshold: CGFloat = 0.4
        let directionThreshold: CGFloat = 10

        // Simulate horizontal movement.
        accumX += 12
        accumY += 2

        XCTAssertTrue(accumX + accumY >= directionThreshold)
        let isVertical = accumY > slopeThreshold * (accumX + accumY)
        XCTAssertFalse(isVertical, "Should detect horizontal direction")
    }

    func testDirectionLockDiagonal() {
        var accumX: CGFloat = 0
        var accumY: CGFloat = 0
        let slopeThreshold: CGFloat = 0.4

        // 45 degree diagonal — vertical component is 50% of total.
        accumX += 8
        accumY += 8

        let isVertical = accumY > slopeThreshold * (accumX + accumY)
        XCTAssertTrue(isVertical, "Diagonal should be classified as vertical (50% > 40%)")
    }

    // MARK: - Squash Boundary

    func testSquashClamp() {
        let width: CGFloat = 900
        let count = 3
        let currentIndex = 1

        let upperBound = CGFloat(currentIndex) * width     // 900
        let lowerBound = -CGFloat(count - 1 - currentIndex) * width  // -900

        // Within bounds.
        XCTAssertEqual(max(lowerBound, min(upperBound, 450)), 450)
        // Above upper.
        XCTAssertEqual(max(lowerBound, min(upperBound, 1200)), 900)
        // Below lower.
        XCTAssertEqual(max(lowerBound, min(upperBound, -1200)), -900)
    }

    // MARK: - Tab Move

    func testMoveTabForward() {
        var tabs = ["A", "B", "C", "D"]
        let currentIndex = 1
        let amount = 1
        let newIndex = max(0, min(tabs.count - 1, currentIndex + amount))

        let tab = tabs.remove(at: currentIndex)
        tabs.insert(tab, at: newIndex)

        XCTAssertEqual(tabs, ["A", "C", "B", "D"])
    }

    func testMoveTabBackward() {
        var tabs = ["A", "B", "C", "D"]
        let currentIndex = 2
        let amount = -1
        let newIndex = max(0, min(tabs.count - 1, currentIndex + amount))

        let tab = tabs.remove(at: currentIndex)
        tabs.insert(tab, at: newIndex)

        XCTAssertEqual(tabs, ["A", "C", "B", "D"])
    }
}
