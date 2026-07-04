import XCTest
@testable import NeonHordeCore

final class StageTests: XCTestCase {
    func testStageBoundaries() {
        XCTAssertEqual(Balance.stage(at: 0), 0)
        XCTAssertEqual(Balance.stage(at: 179.9), 0)
        XCTAssertEqual(Balance.stage(at: 180), 1)
        XCTAssertEqual(Balance.stage(at: 360), 2)
        XCTAssertEqual(Balance.stage(at: 599), 2)
    }

    func testStageGateHealsAndOpensRareDraft() {
        var w = World(seed: 71)
        w.player.hp = 40
        w.testJumpClock(to: 179.9)
        var sawAdvance = false
        var sawDraft = false
        for _ in 0..<30 {
            if w.pendingDraft != nil { break }
            w.tick(WorldInput())
            for e in w.events {
                if case .stageAdvanced(let s) = e { sawAdvance = (s == 1) }
                if case .draftOpened = e { sawDraft = true }
            }
        }
        XCTAssertTrue(sawAdvance, "stage 1 gate must fire at 3:00")
        XCTAssertTrue(sawDraft, "stage gate must open a rare draft")
        XCTAssertNotNil(w.pendingDraft)
        XCTAssertTrue(w.pendingDraft!.rare)
        XCTAssertGreaterThan(w.player.hp, 40, "gate must heal")
    }

    func testStageGateSilentInAttractStyleConfigs() {
        var w = World(seed: 72)
        w.config.draftsEnabled = false
        w.testJumpClock(to: 359.9)
        for _ in 0..<30 { w.tick(WorldInput()) }
        XCTAssertNil(w.pendingDraft)
        XCTAssertEqual(w.stage, 2)
    }
}
