import XCTest
@testable import NeonHorde

final class SmokeTests: XCTestCase {
    func testPaletteThreatRampEndpoints() {
        // Placeholder suite so the test target exists from Phase 1 onward.
        XCTAssertNotNil(Palette.enemy(threat: 0))
        XCTAssertNotNil(Palette.enemy(threat: 1))
    }
}
