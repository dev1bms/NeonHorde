/// The whole game simulation: fixed-timestep, deterministic for a given seed,
/// zero SpriteKit/UIKit imports (GOAL §5). Rendering interpolates on top.
public enum EnemyKind: UInt8, CaseIterable {
    case dart, brick, splitter, weaver, spitter
}

public struct Enemy {
    public var kind: EnemyKind
    public var pos: Vec2
    public var vel: Vec2
    public var hp: Float
    public var radius: Float
    public var phase: Float      // per-entity motion phase (weaver sine, wander)

    public init(kind: EnemyKind, pos: Vec2, hp: Float, radius: Float, phase: Float) {
        self.kind = kind
        self.pos = pos
        self.vel = .zero
        self.hp = hp
        self.radius = radius
        self.phase = phase
    }
}

public struct Player {
    public var pos: Vec2 = .zero
    public var hp: Float = Balance.playerMaxHP
    public var maxHP: Float = Balance.playerMaxHP
    public var iFrames: Float = 0
    public var facing: Vec2 = Vec2(1, 0)   // last nonzero move direction
}

public struct WorldInput {
    /// Joystick vector, magnitude 0...1.
    public var move: Vec2

    public init(move: Vec2 = .zero) {
        self.move = move
    }
}

public struct World {
    public private(set) var tickIndex: UInt64 = 0
    public var rng: SplitMix64
    public var player = Player()
    public private(set) var enemies: [Enemy] = []
    var enemyHash: SpatialHash

    /// Elapsed simulated seconds.
    public var time: Float { Float(tickIndex) * Balance.dt }

    public init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
        enemyHash = SpatialHash(cellSize: Balance.cellSize, capacity: Balance.enemyCap)
        enemies.reserveCapacity(Balance.enemyCap)
    }

    // MARK: - Spawning

    /// Phase 2 stress population: seeded wanderers scattered around the origin.
    public mutating func spawnStressEnemies(_ n: Int) {
        let kinds = EnemyKind.allCases
        for _ in 0..<min(n, Balance.enemyCap - enemies.count) {
            let kind = kinds[rng.int(in: 0...(kinds.count - 1))]
            let stats = Balance.stats(for: kind)
            let angle = rng.float(in: 0...(2 * Float.pi))
            let dist = rng.float(in: 120...900)
            let pos = Vec2(cosApprox(angle) * dist, sinApprox(angle) * dist)
            enemies.append(Enemy(kind: kind, pos: pos, hp: stats.hp,
                                 radius: stats.radius,
                                 phase: rng.float(in: 0...(2 * Float.pi))))
        }
    }

    // MARK: - Tick

    public mutating func tick(_ input: WorldInput) {
        tickIndex &+= 1
        tickPlayer(input)
        tickEnemies()
    }

    private mutating func tickPlayer(_ input: WorldInput) {
        let move = input.move.clamped(to: 1)
        player.pos += move * (Balance.playerSpeed * Balance.dt)
        if move.lengthSquared > 0.01 {
            player.facing = move.normalized
        }
        if player.iFrames > 0 {
            player.iFrames = max(0, player.iFrames - Balance.dt)
        }
    }

    private mutating func tickEnemies() {
        // Rebuild the hash from current positions.
        enemyHash.clear()
        for i in enemies.indices {
            enemyHash.insert(id: Int32(i), x: enemies[i].pos.x, y: enemies[i].pos.y)
        }

        for i in enemies.indices {
            var e = enemies[i]
            let stats = Balance.stats(for: e.kind)

            // Seek the player; weaver adds a perpendicular sine sway.
            var desired = (player.pos - e.pos).normalized
            if e.kind == .weaver {
                e.phase += Balance.dt * 6
                let sway = sinApprox(e.phase) * 0.8
                desired = Vec2(desired.x - desired.y * sway,
                               desired.y + desired.x * sway).normalized
            }

            // Soft separation from neighbors (spatial hash query).
            var push = Vec2.zero
            let sep = Balance.enemySeparationRadius
            let selfX = e.pos.x, selfY = e.pos.y
            enemyHash.forEachNeighbor(x: selfX, y: selfY, radius: sep) { id, nx, ny in
                guard id != Int32(i) else { return }
                let dx = selfX - nx, dy = selfY - ny
                let d2 = dx * dx + dy * dy
                guard d2 > 1e-4, d2 < sep * sep else { return }
                let d = d2.squareRoot()
                let strength = (1 - d / sep)
                push += Vec2(dx / d, dy / d) * strength
            }

            e.vel = desired * stats.speed + push.clamped(to: 1) * Balance.enemySeparationPush
            e.pos += e.vel * Balance.dt
            enemies[i] = e
        }
    }

    // MARK: - State digest (determinism tests)

    /// Order-sensitive FNV-1a digest of the full mutable state.
    public func stateDigest() -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) {
            h = (h ^ v) &* 0x100000001b3
        }
        mix(tickIndex)
        mix(UInt64(player.pos.x.bitPattern))
        mix(UInt64(player.pos.y.bitPattern))
        mix(UInt64(player.hp.bitPattern))
        for e in enemies {
            mix(UInt64(e.kind.rawValue))
            mix(UInt64(e.pos.x.bitPattern))
            mix(UInt64(e.pos.y.bitPattern))
            mix(UInt64(e.hp.bitPattern))
        }
        return h
    }
}

// MARK: - Deterministic trig
// Foundation's sin/cos are fine on one machine, but keeping Core free of libm
// keeps determinism unambiguous across the app and native test targets.

/// Bhaskara-style sine approximation, accurate to ~0.002 over the full circle.
@inlinable public func sinApprox(_ x: Float) -> Float {
    let twoPi = 2 * Float.pi
    var t = x.truncatingRemainder(dividingBy: twoPi)
    if t < 0 { t += twoPi }
    let sign: Float = t > .pi ? -1 : 1
    if t > .pi { t -= .pi }
    let num = 16 * t * (.pi - t)
    let den = 5 * .pi * .pi - 4 * t * (.pi - t)
    return sign * num / den
}

@inlinable public func cosApprox(_ x: Float) -> Float {
    sinApprox(x + .pi / 2)
}
