import XCTest
@testable import NeonHordeCore

/// GOAL Phase 9: 30 minutes of accelerated game time across consecutive
/// bot runs — no crashes, every pool bounded, at escalating Overdrive tiers.
final class SoakTests: XCTestCase {
    func testThirtyMinuteGameTimeSoak() {
        var totalTicks = 0
        var runs = 0
        var victories = 0
        var seed: UInt64 = 424_242
        var meta = MetaState()
        meta.upgradeRanks[MetaUpgradeKind.maxHP.rawValue] = 3
        meta.upgradeRanks[MetaUpgradeKind.damage.rawValue] = 3

        while totalTicks < 108_000 {   // 30 min of simulated time
            var w = World(seed: seed, meta: meta)
            w.config.overdriveTier = runs % 3   // rotate difficulty tiers
            var bot = KitingBot(seed: seed)
            while w.state == .playing, totalTicks < 108_000 {
                if let draft = w.pendingDraft {
                    w.applyDraft(bot.pickDraft(draft, world: w))
                    continue
                }
                w.tick(WorldInput(move: bot.move(world: w)))
                totalTicks += 1
                if totalTicks % 600 == 0 {   // bounds audit every 10s of game time
                    XCTAssertLessThanOrEqual(w.enemies.count, Balance.enemyCap)
                    XCTAssertLessThanOrEqual(w.projectiles.count, Balance.projectileCap)
                    XCTAssertLessThanOrEqual(w.gems.count, Balance.gemCap)
                    XCTAssertLessThanOrEqual(w.enemyShots.count, Balance.enemyShotCap)
                    XCTAssertLessThanOrEqual(w.chests.count, 8)
                    XCTAssertLessThanOrEqual(w.events.count, 700,
                                             "event buffer ballooning (\(w.events.count))")
                }
            }
            if w.state == .victory { victories += 1 }
            runs += 1
            seed &+= 7919
        }
        print("SOAK 30min game time: \(runs) runs, \(victories) victories, pools bounded")
        XCTAssertGreaterThan(runs, 1)
    }
}
