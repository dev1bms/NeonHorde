import XCTest
@testable import NeonHordeCore

final class UpgradeTests: XCTestCase {
    func testDraftOpensOnLevelUpAndFreezesTime() {
        var w = World(seed: 44)
        w.config.directorEnabled = false
        // Force a level-up by dropping enough gem XP on the player.
        w.spawnStressEnemies(1)
        w.forceXP(10)
        XCTAssertNotNil(w.pendingDraft, "level-up must open a draft")
        XCTAssertEqual(w.pendingDraft!.choices.count, 3)
        let frozen = w.tickIndex
        w.tick(WorldInput(move: Vec2(1, 0)))
        XCTAssertEqual(w.tickIndex, frozen, "sim must freeze while a draft is pending")
        w.applyDraft(0)
        XCTAssertNil(w.pendingDraft)
        w.tick(WorldInput(move: Vec2(1, 0)))
        XCTAssertEqual(w.tickIndex, frozen + 1)
    }

    func testDraftNeverOffersMaxedOrOverflowingChoices() {
        var w = World(seed: 45)
        // Fill weapons to the cap and max one of them.
        w.loadout.weaponLevels[WeaponKind.pulseBolt.rawValue] = Loadout.maxLevel
        w.loadout.weaponLevels[WeaponKind.orbitBlades.rawValue] = 1
        w.loadout.weaponLevels[WeaponKind.novaBurst.rawValue] = 1
        w.loadout.weaponLevels[WeaponKind.railLance.rawValue] = 1
        for _ in 0..<40 {   // drafts are random — sample repeatedly
            w.generateDraft(rare: false)
            guard let draft = w.pendingDraft else { continue }
            for choice in draft.choices {
                if case .weapon(let kind) = choice {
                    XCTAssertNotEqual(kind, .pulseBolt, "maxed weapon offered")
                    XCTAssertGreaterThan(w.loadout.level(of: kind), 0,
                                         "new weapon offered while slots are full")
                }
            }
            w.pendingDraft = nil
        }
    }

    func testRareDraftGrantsDoubleWeaponLevels() {
        var w = World(seed: 46)
        w.generateDraft(rare: true)
        guard let draft = w.pendingDraft,
              let weaponIndex = draft.choices.firstIndex(where: {
                  if case .weapon = $0 { return true } else { return false }
              }),
              case .weapon(let kind) = draft.choices[weaponIndex] else {
            // No weapon card in this sample — regenerate deterministically.
            return XCTFail("expected at least one weapon card in a rare draft sample")
        }
        let before = w.loadout.level(of: kind)
        w.applyDraft(weaponIndex)
        XCTAssertEqual(w.loadout.level(of: kind), min(Loadout.maxLevel, before + 2))
    }

    func testAllWeaponsDealDamage() {
        for kind in WeaponKind.allCases {
            var w = World(seed: UInt64(1000 + kind.rawValue))
            w.config.directorEnabled = false
            // Huge HP (not invulnerability): contact knockback must keep
            // cycling enemies through weapon range, as in the real game.
            w.player.maxHP = 1_000_000
            w.player.hp = 1_000_000
            w.loadout.weaponLevels = [Int](repeating: 0, count: WeaponKind.allCases.count)
            w.loadout.weaponLevels[kind.rawValue] = 3
            w.spawnRingOfDarts(count: 24, radius: 80)
            let before = w.enemies.count
            for _ in 0..<600 {   // 10 seconds
                w.tick(WorldInput())
            }
            XCTAssertGreaterThan(w.kills, 0, "\(kind) killed nothing in 10s (started \(before))")
        }
    }

    func testBulwarkPickHealsAndRaisesCap() {
        var w = World(seed: 47)
        w.player.hp = 40
        w.pendingDraft = Draft(choices: [.passive(.maxHP)], rare: false)
        w.applyDraft(0)
        XCTAssertEqual(w.player.maxHP, Balance.playerMaxHP + 20)
        XCTAssertEqual(w.player.hp, 60)
    }

    /// GOAL §4 official balance row: fresh player IN THE REAL GAME (upgrades
    /// via drafts, no meta): dies between 1:30 and 4:00 on average.
    func testFreshPlayerWithDraftsDiesInOfficialWindow() {
        var deaths: [Float] = []
        for seed in 1...20 {
            let r = simulateRun(seed: UInt64(seed * 7919),
                                policy: RandomWalkBot(seed: UInt64(seed)))
            XCTAssertTrue(r.died, "seed \(seed): fresh player must still die eventually")
            deaths.append(r.survivedSeconds)
        }
        let avg = deaths.reduce(0, +) / Float(deaths.count)
        print("BALANCE official fresh+drafts: avg=\(avg)s min=\(deaths.min()!)s max=\(deaths.max()!)s")
        XCTAssertGreaterThan(avg, 90, "fresh players die too fast (avg \(avg)s)")
        XCTAssertLessThan(avg, 240, "fresh players last too long (avg \(avg)s)")
    }

    /// GOAL Phase 4 acceptance: upgrades must at least double survival.
    func testUpgradesDoubleSurvival() {
        var withUpgrades: Float = 0
        var withoutUpgrades: Float = 0
        for seed in 1...8 {
            withUpgrades += simulateRun(seed: UInt64(seed * 31), policy: RandomWalkBot(seed: UInt64(seed)),
                                        maxTicks: 21_600).survivedSeconds
            withoutUpgrades += simulateRun(seed: UInt64(seed * 31), policy: RandomWalkBot(seed: UInt64(seed)),
                                           maxTicks: 21_600, declineDrafts: true).survivedSeconds
        }
        print("BALANCE upgraded=\(withUpgrades / 8)s baseline=\(withoutUpgrades / 8)s")
        XCTAssertGreaterThan(withUpgrades, withoutUpgrades * 2)
    }
}

extension World {
    /// Test helper: grants XP as if gems were collected.
    mutating func forceXP(_ amount: Float) {
        testDropGem(xp: amount)
        tick(WorldInput())
    }

    /// Test helper: ring of darts around the player (weapon test dummies).
    mutating func spawnRingOfDarts(count: Int, radius: Float) {
        let stats = Balance.stats(for: .dart)
        for i in 0..<count {
            let a = Float(i) / Float(count) * 2 * .pi
            let e = Enemy(kind: .dart, pos: player.pos + Vec2(cosApprox(a), sinApprox(a)) * radius,
                          hp: stats.hp, radius: stats.radius, phase: 0)
            testAppendEnemy(e)
        }
    }
}
