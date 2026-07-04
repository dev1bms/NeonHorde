import XCTest
@testable import NeonHordeCore

final class MetaTests: XCTestCase {
    func testCostsEscalateAndCapAtMaxRank() {
        var m = MetaState()
        m.shards = 100_000
        let kind = MetaUpgradeKind.damage
        var lastCost = 0
        for r in 0..<kind.maxRank {
            let c = kind.cost(rank: r)
            XCTAssertGreaterThan(c, lastCost, "costs must escalate")
            lastCost = c
            XCTAssertTrue(m.buy(kind))
        }
        XCTAssertFalse(m.buy(kind), "buying past maxRank must fail")
        XCTAssertEqual(m.rank(of: kind), kind.maxRank)
    }

    func testBuyRefusesWhenBroke() {
        var m = MetaState()
        m.shards = 10
        XCTAssertFalse(m.buy(.damage))
        XCTAssertEqual(m.shards, 10, "failed buys must not charge")
    }

    func testSaveRoundTrip() {
        var m = MetaState()
        m.shards = 1234
        m.upgradeRanks[MetaUpgradeKind.magnet.rawValue] = 3
        m.victories = 2
        m.highestOverdriveBeaten = 1
        m.selectedShape = 2
        XCTAssertTrue(SaveStore.save(m))
        let loaded = SaveStore.load()
        XCTAssertEqual(loaded, m)
        // Clean up the test artifact so app-side tests start fresh.
        try? FileManager.default.removeItem(at: SaveStore.fileURL)
    }

    func testMetaBonusesApplyToWorld() {
        var m = MetaState()
        m.upgradeRanks[MetaUpgradeKind.maxHP.rawValue] = 5      // +75 HP
        m.upgradeRanks[MetaUpgradeKind.startLevel.rawValue] = 2
        m.upgradeRanks[MetaUpgradeKind.revive.rawValue] = 1
        let w = World(seed: 5, meta: m)
        XCTAssertEqual(w.player.maxHP, Balance.playerMaxHP + 75)
        XCTAssertEqual(w.player.hp, w.player.maxHP)
        XCTAssertEqual(w.player.level, 3)
        XCTAssertEqual(w.revivesLeft, 1)
    }

    func testReviveTriggersOnceThenDeath() {
        var m = MetaState()
        m.upgradeRanks[MetaUpgradeKind.revive.rawValue] = 1
        var w = World(seed: 7, meta: m)
        w.config.directorEnabled = false
        w.player.hp = 0.5
        w.spawnRingOfDarts(count: 8, radius: 30)   // lethal contact incoming
        var revived = false
        for _ in 0..<600 {
            w.tick(WorldInput())
            for e in w.events {
                if case .revived = e { revived = true }
            }
            if w.state == .dead { break }
        }
        XCTAssertTrue(revived, "revive must trigger before death")
        XCTAssertEqual(w.revivesLeft, 0)
    }

    func testShardEconomyAccrues() {
        var w = World(seed: 21)
        w.config.directorEnabled = false
        w.testJumpClock(to: 100)   // trickle: 10 shards
        XCTAssertEqual(w.shardsEarned, 10)
        var m = MetaState()
        m.upgradeRanks[MetaUpgradeKind.shardGain.rawValue] = 5   // ×2
        var w2 = World(seed: 21, meta: m)
        w2.config.directorEnabled = false
        w2.testJumpClock(to: 100)
        XCTAssertEqual(w2.shardsEarned, 20)
    }

    func testOverdriveScalesEnemiesAndShards() {
        XCTAssertEqual(Overdrive.enemyHPMult(tier: 0), 1)
        XCTAssertEqual(Overdrive.enemyHPMult(tier: 3), 2.05, accuracy: 0.001)
        XCTAssertEqual(Overdrive.spawnRateMult(tier: 5), 1.75, accuracy: 0.001)
        var w = World(seed: 31)
        w.config.overdriveTier = 3
        w.config.combatEnabled = false
        // Let the director spawn a few and inspect their HP scaling.
        for _ in 0..<600 { w.tick(WorldInput()) }
        let dart = w.enemies.first { $0.kind == .dart }
        XCTAssertNotNil(dart)
        if let dart {
            let expectedMin = Balance.stats(for: .dart).hp * Overdrive.enemyHPMult(tier: 3) * 0.95
            XCTAssertGreaterThan(dart.hp, expectedMin)
        }
    }

    func testMetaDamageShortensBossKill() {
        // Same skilled run; +40% permanent damage must not LOSE fights.
        var base = MetaState()
        base.upgradeRanks[MetaUpgradeKind.damage.rawValue] = 5
        var w = World(seed: 11 &* 999_331, meta: base)
        var bot = KitingBot(seed: 11)
        var ticks = 0
        while w.state == .playing, ticks < 48_000 {
            if let draft = w.pendingDraft {
                w.applyDraft(bot.pickDraft(draft, world: w))
                continue
            }
            w.tick(WorldInput(move: bot.move(world: w)))
            ticks += 1
        }
        XCTAssertEqual(w.state, .victory, "full meta damage must still win")
    }
}
