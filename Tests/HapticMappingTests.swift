import XCTest
import NeonHordeCore
@testable import NeonHorde

/// GOAL Phase 7 acceptance: haptics are verified by asserting the pure
/// event→pattern mapping (feel-check itself is deferred to TestFlight).
final class HapticMappingTests: XCTestCase {
    func testEventMapping() {
        XCTAssertEqual(HapticMapping.haptic(for: .gemCollected(.zero)), .light)
        XCTAssertEqual(HapticMapping.haptic(for: .playerHit(5)), .medium)
        XCTAssertEqual(HapticMapping.haptic(for: .leveledUp(3)), .heavy)
        XCTAssertEqual(HapticMapping.haptic(for: .bossSpawned), .heavy)
        XCTAssertEqual(HapticMapping.haptic(for: .victory), .heavy)
        XCTAssertEqual(HapticMapping.haptic(for: .playerDied), .heavy)
        XCTAssertEqual(HapticMapping.haptic(for: .chestCollected(.zero)), .heavy)
        // High-frequency combat events must NOT vibrate.
        XCTAssertNil(HapticMapping.haptic(for: .enemyDied(.zero, .dart)))
        XCTAssertNil(HapticMapping.haptic(for: .damageDealt(.zero, 40)))
        XCTAssertNil(HapticMapping.haptic(for: .novaBurst(.zero, 100)))
    }
}
