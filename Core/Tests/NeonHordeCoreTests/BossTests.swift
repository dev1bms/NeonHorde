import XCTest
@testable import NeonHordeCore

final class BossTests: XCTestCase {
    /// Fast-forward a world to just before boss time with a competent build.
    private func worldAtBossDoor(seed: UInt64) -> (World, KitingBot) {
        var w = World(seed: seed)
        var bot = KitingBot(seed: seed)
        while w.time < Balance.bossSpawnTime + 2, w.state == .playing {
            if let draft = w.pendingDraft {
                w.applyDraft(bot.pickDraft(draft, world: w))
                continue
            }
            w.tick(WorldInput(move: bot.move(world: w)))
        }
        return (w, bot)
    }

    func testTimelineElitesAndBossSpawn() {
        var w = World(seed: 606)
        var bot = KitingBot(seed: 6)
        var sawElite = false
        var sawBoss = false
        var ticks = 0
        while w.state == .playing, ticks < 36_000, !sawBoss {
            if let draft = w.pendingDraft {
                w.applyDraft(bot.pickDraft(draft, world: w))
                continue
            }
            w.tick(WorldInput(move: bot.move(world: w)))
            ticks += 1
            for e in w.events {
                if case .eliteSpawned = e { sawElite = true }
                if case .bossSpawned = e { sawBoss = true }
            }
        }
        XCTAssertTrue(sawElite, "no elite spawned before death/boss (died at \(w.time)s)")
        XCTAssertTrue(sawBoss, "kiting bot never reached PRIME (state \(w.state), t=\(w.time))")
    }

    /// Deterministic: a dying elite must drop a chest, and collecting it
    /// opens a RARE draft.
    func testEliteDropsChestAndChestOpensRareDraft() {
        var w = World(seed: 608)
        w.config.directorEnabled = false
        w.testJumpClock(to: 150)
        w.testSpawnEliteNow()
        XCTAssertTrue(w.enemies.contains { $0.elite })
        // Kill it.
        for i in w.enemies.indices where w.enemies[i].elite {
            w.enemies[i].hp = -1
        }
        w.tick(WorldInput())
        XCTAssertEqual(w.chests.count, 1, "dead elite must drop a chest")
        // Walk into the chest.
        w.player.pos = w.chests[0].pos
        w.tick(WorldInput())
        XCTAssertNotNil(w.pendingDraft)
        XCTAssertTrue(w.pendingDraft!.rare, "chest draft must be rare tier")
    }

    /// The full dream run: a skilled bot with drafts beats PRIME.
    func testKitingBotCanBeatPrime() {
        var victories = 0
        for seed in [11, 22, 33, 44, 55] as [UInt64] {
            var w = World(seed: seed)
            var bot = KitingBot(seed: seed)
            var ticks = 0
            while w.state == .playing, ticks < 48_000 {
                if let draft = w.pendingDraft {
                    w.applyDraft(bot.pickDraft(draft, world: w))
                    continue
                }
                w.tick(WorldInput(move: bot.move(world: w)))
                ticks += 1
            }
            if w.state == .victory { victories += 1 }
        }
        print("BALANCE boss: kiting bot victories = \(victories)/5")
        XCTAssertGreaterThanOrEqual(victories, 2,
                                    "a skilled draft build must be able to beat PRIME")
    }

    /// Enrage compounding provably ends stalled fights: a stationary tank that
    /// cannot kill PRIME must still die within ~2 minutes past enrage.
    func testEnrageEndsStalls() {
        var w = World(seed: 909)
        w.config.directorEnabled = false
        w.player.maxHP = 10_000
        w.player.hp = 10_000
        w.testJumpClock(to: Balance.bossEnrageTime)
        w.spawnBoss()
        var ticks = 0
        while w.state == .playing, ticks < 60 * 150 {   // 150s budget
            w.tick(WorldInput())                        // stationary, starter bolt only
            ticks += 1
        }
        XCTAssertEqual(w.state, .dead,
                       "10k-HP stationary player must be crushed by enrage within 150s")
    }

    func testEnrageMultiplierCompounds() {
        XCTAssertEqual(Balance.enrageMultiplier(secondsPastEnrage: 0), 1, accuracy: 0.001)
        let m60 = Balance.enrageMultiplier(secondsPastEnrage: 60)
        XCTAssertEqual(m60, pow(1.03, 60), accuracy: pow(1.03, 60) * 0.02)
        XCTAssertGreaterThan(Balance.enrageMultiplier(secondsPastEnrage: 120), m60 * m60 * 0.9)
    }

    func testVictoryStateStopsTheWorld() {
        var w = World(seed: 707)
        w.config.directorEnabled = false
        w.spawnBoss()
        w.testSetBossHP(-1)   // dies on its next tick
        w.tick(WorldInput())
        XCTAssertEqual(w.state, .victory)
        let frozen = w.tickIndex
        w.tick(WorldInput(move: Vec2(1, 0)))
        XCTAssertEqual(w.tickIndex, frozen, "victory must freeze the sim")
    }
}
