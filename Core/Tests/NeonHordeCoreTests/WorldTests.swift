import XCTest
@testable import NeonHordeCore

final class WorldTests: XCTestCase {
    func testDeterminismSameSeedSameDigest() {
        var a = World(seed: 99)
        var b = World(seed: 99)
        a.spawnStressEnemies(300)
        b.spawnStressEnemies(300)
        let input = WorldInput(move: Vec2(0.7, -0.2))
        for _ in 0..<600 {
            a.tick(input)
            b.tick(input)
        }
        XCTAssertEqual(a.stateDigest(), b.stateDigest())
        XCTAssertNotEqual(a.stateDigest(), World(seed: 100).stateDigest())
    }

    func testPlayerMovesWithInput() {
        var w = World(seed: 1)
        for _ in 0..<60 {
            w.tick(WorldInput(move: Vec2(1, 0)))
        }
        // One second at full speed ≈ playerSpeed points.
        XCTAssertEqual(w.player.pos.x, Balance.playerSpeed, accuracy: 1.0)
        XCTAssertEqual(w.player.pos.y, 0, accuracy: 0.001)
    }

    func testEnemiesSeekPlayer() {
        var w = World(seed: 5)
        w.spawnStressEnemies(50)
        let before = w.enemies.map { $0.pos.distanceSquared(to: w.player.pos) }
        for _ in 0..<120 {
            w.tick(WorldInput())
        }
        var closer = 0
        for (i, e) in w.enemies.enumerated()
        where e.pos.distanceSquared(to: w.player.pos) < before[i] { closer += 1 }
        // Separation pushes some around, but the strong majority must approach.
        XCTAssertGreaterThan(closer, 40)
    }

    func testEnemyCapRespected() {
        var w = World(seed: 3)
        w.spawnStressEnemies(10_000)
        XCTAssertLessThanOrEqual(w.enemies.count, Balance.enemyCap)
    }

    /// GOAL Contract rule 6: World.tick ≤ 4 ms at 500 enemies.
    func testTickBudgetAt500Enemies() {
        var w = World(seed: 42)
        w.spawnStressEnemies(500)
        let input = WorldInput(move: Vec2(0.5, 0.5))
        // Warm up.
        for _ in 0..<60 { w.tick(input) }
        let ticks = 600
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<ticks { w.tick(input) }
        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        let perTick = elapsedMS / Double(ticks)
        XCTAssertLessThan(perTick, 4.0, "World.tick averaged \(perTick) ms at 500 enemies")
    }

    func testSinApproxAccuracy() {
        for i in 0..<1000 {
            let x = Float(i) * 0.02 - 10
            XCTAssertEqual(sinApprox(x), sin(x), accuracy: 0.005)
            XCTAssertEqual(cosApprox(x), cos(x), accuracy: 0.005)
        }
    }
}
