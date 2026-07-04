import XCTest
@testable import NeonHordeCore

/// GOAL §4 Balance targets, enforced across seeds. These are the guardrails
/// every future tuning change must keep green.
final class BalanceTests: XCTestCase {
    /// Pre-upgrade baseline: random-walk bot with only the starter bolt.
    /// The official GOAL §4 window (1:30–4:00) applies to the real game where
    /// level-ups grant upgrades — Phase 4's upgrade-picking bot enforces it.
    /// Until then the un-upgraded floor must be: survivable start, inevitable
    /// death, no sub-30s ambushes.
    func testFreshPlayerPreUpgradeWindow() {
        var deaths: [Float] = []
        for seed in 1...20 {
            let r = simulateRun(seed: UInt64(seed * 7919),
                                policy: RandomWalkBot(seed: UInt64(seed)),
                                declineDrafts: true)   // starter-bolt-only floor
            XCTAssertTrue(r.died, "seed \(seed): random-walk bot must not survive a full run")
            deaths.append(r.survivedSeconds)
        }
        let avg = deaths.reduce(0, +) / Float(deaths.count)
        let minD = deaths.min()!
        let maxD = deaths.max()!
        print("BALANCE fresh-player deaths: avg=\(avg)s min=\(minD)s max=\(maxD)s")
        XCTAssertGreaterThan(avg, 40, "un-upgraded runs end too fast (avg \(avg)s)")
        XCTAssertLessThan(avg, 120, "un-upgraded runs drag (avg \(avg)s)")
        XCTAssertGreaterThan(minD, 30, "worst-case fresh death unreasonably early (\(minD)s)")
    }

    /// Skilled movement alone (kiting, still no upgrades) must clearly beat
    /// random walking — skill expression exists even before the draft system.
    func testKitingOutlivesRandomWalk() {
        var kitingTotal: Float = 0
        var randomTotal: Float = 0
        for seed in 1...5 {
            kitingTotal += simulateRun(seed: UInt64(seed * 104_729),
                                       policy: KitingBot(seed: UInt64(seed)),
                                       maxTicks: 18_000).survivedSeconds
            randomTotal += simulateRun(seed: UInt64(seed * 104_729),
                                       policy: RandomWalkBot(seed: UInt64(seed)),
                                       maxTicks: 18_000).survivedSeconds
        }
        print("BALANCE kiting=\(kitingTotal / 5)s random=\(randomTotal / 5)s")
        XCTAssertGreaterThan(kitingTotal, randomTotal * 1.3,
                             "kiting must outlive random walk by ≥30%")
    }

    func testKillsAndLevelsAccumulate() {
        let r = simulateRun(seed: 12345, policy: KitingBot(seed: 5), maxTicks: 9_000)
        XCTAssertGreaterThan(r.kills, 20, "a multi-minute run should kill plenty")
        XCTAssertGreaterThan(r.level, 2, "XP gems should drive level-ups")
    }

    func testCombatDeterminism() {
        func digestAfterRun(_ seed: UInt64) -> UInt64 {
            var world = World(seed: seed)
            var bot = KitingBot(seed: 1)
            for _ in 0..<3600 {
                world.tick(WorldInput(move: bot.move(world: world)))
            }
            return world.stateDigest()
        }
        XCTAssertEqual(digestAfterRun(777), digestAfterRun(777))
    }
}
