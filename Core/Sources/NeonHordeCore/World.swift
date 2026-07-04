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
    public var knock: Vec2       // decaying knockback velocity

    public init(kind: EnemyKind, pos: Vec2, hp: Float, radius: Float, phase: Float) {
        self.kind = kind
        self.pos = pos
        self.vel = .zero
        self.hp = hp
        self.radius = radius
        self.phase = phase
        self.knock = .zero
    }
}

public struct Projectile {
    public var pos: Vec2
    public var vel: Vec2
    public var damage: Float
    public var radius: Float
    public var life: Float       // remaining seconds
    public var pierce: Int       // remaining enemies it may pass through
    public var homing = false    // seeker swarm steering
    public var mine = false      // stationary, proximity-triggered
    public var aoe: Float = 0    // mine blast radius
}

public struct Gem {
    public var pos: Vec2
    public var xp: Float
    public var magnetized: Bool
}

public struct Player {
    public var pos: Vec2 = .zero
    public var hp: Float = Balance.playerMaxHP
    public var maxHP: Float = Balance.playerMaxHP
    public var iFrames: Float = 0
    public var facing: Vec2 = Vec2(1, 0)   // last nonzero move direction
    public var xp: Float = 0
    public var level: Int = 1
}

/// A pending level-up choice. While non-nil the simulation is frozen.
public struct Draft {
    public let choices: [UpgradeChoice]
    public let rare: Bool
}

public struct WorldInput {
    /// Joystick vector, magnitude 0...1.
    public var move: Vec2

    public init(move: Vec2 = .zero) {
        self.move = move
    }
}

/// One-tick notifications for the render/audio layer (cleared every tick).
public enum WorldEvent {
    case enemyDied(Vec2, EnemyKind)
    case playerHit(Float)
    case gemCollected(Vec2)
    case leveledUp(Int)
    case playerDied
    case draftOpened
    case novaBurst(Vec2, Float)              // center, radius
    case railLance(Vec2, Vec2, Float)        // origin, direction, length
    case chainArc([Vec2])                    // polyline: player → chained enemies
    case mineExploded(Vec2, Float)           // center, radius
}

public enum GameState: Equatable {
    case playing
    case dead
}

public struct WorldConfig {
    /// Half-extents of the visible viewport in world points (camera-centered);
    /// the Director spawns just beyond this. Set by the scene at startup.
    public var viewHalf = Vec2(215, 466)
    /// Disabled in stress/demo harnesses.
    public var directorEnabled = true
    /// When false, weapons and contact damage are skipped (pure-movement
    /// harnesses: stress scene, seek tests, attract backgrounds).
    public var combatEnabled = true
    /// Player takes no damage (weapon-viability tests, DEMO screenshot mode).
    public var playerInvulnerable = false

    public init() {}
}

public struct World {
    public private(set) var tickIndex: UInt64 = 0
    public var rng: SplitMix64
    public var config = WorldConfig()
    public internal(set) var state: GameState = .playing
    public var player = Player()
    public internal(set) var enemies: [Enemy] = []
    public internal(set) var projectiles: [Projectile] = []
    public internal(set) var gems: [Gem] = []
    public internal(set) var events: [WorldEvent] = []
    public internal(set) var kills: Int = 0
    public internal(set) var loadout = Loadout()
    public internal(set) var pendingDraft: Draft?
    var queuedLevelUps = 0
    var weaponCooldowns = [Float](repeating: 0, count: WeaponKind.allCases.count)
    public internal(set) var orbitAngle: Float = 0
    public internal(set) var beamAngle: Float = 0
    var enemyHash: SpatialHash
    var spawnAccumulator: Float = 0

    /// Elapsed simulated seconds.
    public var time: Float { Float(tickIndex) * Balance.dt }

    public init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
        enemyHash = SpatialHash(cellSize: Balance.cellSize, capacity: Balance.enemyCap)
        enemies.reserveCapacity(Balance.enemyCap)
        projectiles.reserveCapacity(Balance.projectileCap)
        gems.reserveCapacity(Balance.gemCap)
        events.reserveCapacity(64)
        loadout.weaponLevels[WeaponKind.pulseBolt.rawValue] = 1   // starter weapon
    }

    // MARK: - Tick

    public mutating func tick(_ input: WorldInput) {
        events.removeAll(keepingCapacity: true)
        guard state == .playing, pendingDraft == nil else { return }   // draft freezes time
        tickIndex &+= 1

        tickPlayerMovement(input)
        if config.directorEnabled {
            tickDirector()
        }
        rebuildEnemyHash()
        tickEnemies()
        if config.combatEnabled {
            tickContactDamage()
            tickWeaponSystems()
            tickProjectiles()
            tickGems()
        }
        sweepDead()

        if player.hp <= 0 {
            state = .dead
            events.append(.playerDied)
        }
    }

    private mutating func tickPlayerMovement(_ input: WorldInput) {
        let move = input.move.clamped(to: 1)
        player.pos += move * (Balance.playerSpeed * loadout.moveSpeedMultiplier * Balance.dt)
        if move.lengthSquared > 0.01 {
            player.facing = move.normalized
        }
        if player.iFrames > 0 {
            player.iFrames = max(0, player.iFrames - Balance.dt)
        }
    }

    private mutating func rebuildEnemyHash() {
        enemyHash.clear()
        for i in enemies.indices {
            enemyHash.insert(id: Int32(i), x: enemies[i].pos.x, y: enemies[i].pos.y)
        }
    }

    // MARK: - Enemies

    private mutating func tickEnemies() {
        for i in enemies.indices {
            var e = enemies[i]
            let stats = Balance.stats(for: e.kind)

            var desired = (player.pos - e.pos).normalized
            switch e.kind {
            case .weaver:
                e.phase += Balance.dt * 6
                let sway = sinApprox(e.phase) * 0.8
                desired = Vec2(desired.x - desired.y * sway,
                               desired.y + desired.x * sway).normalized
            case .spitter:
                // Keeps its distance (ranged behavior lands with its shots in Phase 5).
                let d2 = e.pos.distanceSquared(to: player.pos)
                if d2 < 240 * 240 { desired = desired * -0.6 }
            default:
                break
            }

            // Soft separation, capped per entity (dense-clump O(n²) guard).
            var push = Vec2.zero
            var visited = 0
            let sep = Balance.enemySeparationRadius
            let selfX = e.pos.x, selfY = e.pos.y
            enemyHash.forEachNeighborUntil(x: selfX, y: selfY, radius: sep) { id, nx, ny in
                guard id != Int32(i) else { return true }
                let dx = selfX - nx, dy = selfY - ny
                let d2 = dx * dx + dy * dy
                guard d2 > 1e-4, d2 < sep * sep else { return true }
                let d = d2.squareRoot()
                push += Vec2(dx / d, dy / d) * (1 - d / sep)
                visited += 1
                return visited < Balance.separationNeighborCap
            }

            e.vel = desired * stats.speed + push.clamped(to: 1) * Balance.enemySeparationPush + e.knock
            e.knock = e.knock * (1 - 6 * Balance.dt)   // exponential knockback decay
            e.pos += e.vel * Balance.dt

            // Hard collision with the player: enemies press against the
            // contact ring, never tunnel through the core (keeps them inside
            // orbit-blade reach and reads correctly on screen).
            let ringR = Balance.playerRadius + e.radius
            let dp2 = e.pos.distanceSquared(to: player.pos)
            if dp2 < ringR * ringR, dp2 > 1e-6 {
                let d = dp2.squareRoot()
                e.pos = player.pos + (e.pos - player.pos) * (ringR / d)
            }

            e.phase += Balance.dt
            enemies[i] = e
        }
    }

    private mutating func tickContactDamage() {
        guard !config.playerInvulnerable, player.iFrames <= 0 else { return }
        let px = player.pos.x, py = player.pos.y
        let reach = Balance.playerRadius + 18   // max enemy radius
        var hitDamage: Float = 0
        var hitIndex: Int32 = -1
        enemyHash.forEachNeighborUntil(x: px, y: py, radius: reach) { [enemies] id, _, _ in
            let e = enemies[Int(id)]
            let rr = Balance.playerRadius + e.radius
            if e.pos.distanceSquared(to: Vec2(px, py)) <= rr * rr {
                hitDamage = Balance.stats(for: e.kind).contactDamage
                hitIndex = id
                return false
            }
            return true
        }
        guard hitIndex >= 0 else { return }
        let effective = max(1, hitDamage - loadout.flatArmor)
        player.hp -= effective
        player.iFrames = Balance.playerIFrames
        events.append(.playerHit(effective))
        // Knock the attacker back off the player.
        let away = (enemies[Int(hitIndex)].pos - player.pos).normalized
        enemies[Int(hitIndex)].knock = away * Balance.contactKnockback
    }

    private mutating func tickProjectiles() {
        // Gather-then-apply: never mutate `enemies` inside a hash query
        // closure (Swift exclusivity). One scratch buffer per tick.
        var candidates: [Int32] = []
        candidates.reserveCapacity(32)
        for i in projectiles.indices {
            var p = projectiles[i]
            guard p.life > 0 else { continue }
            p.life -= Balance.dt

            if p.mine {
                tickMine(&p, scratch: &candidates)
                projectiles[i] = p
                continue
            }

            if p.homing {
                // Limited-turn-rate steering toward the nearest enemy.
                if let t = nearestEnemyIndex(to: p.pos, maxDistance: 320) {
                    let desired = (enemies[t].pos - p.pos).normalized
                    let speed = p.vel.length
                    let turn: Float = 5.5 * Balance.dt
                    let blended = Vec2(p.vel.x / max(speed, 1) + desired.x * turn,
                                       p.vel.y / max(speed, 1) + desired.y * turn).normalized
                    p.vel = blended * speed
                }
            }
            p.pos += p.vel * Balance.dt

            candidates.removeAll(keepingCapacity: true)
            enemyHash.forEachNeighbor(x: p.pos.x, y: p.pos.y, radius: p.radius + 18) { id, _, _ in
                candidates.append(id)
            }
            for id in candidates {
                let idx = Int(id)
                guard enemies[idx].hp > 0 else { continue }   // already dead this tick
                let rr = p.radius + enemies[idx].radius
                guard enemies[idx].pos.distanceSquared(to: p.pos) <= rr * rr else { continue }
                enemies[idx].hp -= p.damage
                if p.pierce > 0 {
                    p.pierce -= 1
                } else {
                    p.life = 0
                    break
                }
            }
            projectiles[i] = p
        }
    }

    private mutating func tickMine(_ mine: inout Projectile, scratch: inout [Int32]) {
        // Armed after a short delay (mine.life counts down from 10; armed below 9.5).
        guard mine.life < 9.5 else { return }
        scratch.removeAll(keepingCapacity: true)
        var triggered = false
        enemyHash.forEachNeighborUntil(x: mine.pos.x, y: mine.pos.y, radius: 26 + 18) { [enemies] id, _, _ in
            let e = enemies[Int(id)]
            let rr = 26 + e.radius
            if e.hp > 0, e.pos.distanceSquared(to: mine.pos) <= rr * rr {
                triggered = true
                return false
            }
            return true
        }
        guard triggered else { return }
        scratch.removeAll(keepingCapacity: true)
        enemyHash.forEachNeighbor(x: mine.pos.x, y: mine.pos.y, radius: mine.aoe + 18) { id, _, _ in
            scratch.append(id)
        }
        for id in scratch {
            let idx = Int(id)
            let rr = mine.aoe + enemies[idx].radius
            if enemies[idx].pos.distanceSquared(to: mine.pos) <= rr * rr {
                enemies[idx].hp -= mine.damage
            }
        }
        events.append(.mineExploded(mine.pos, mine.aoe))
        mine.life = 0
    }

    // MARK: - Gems

    private mutating func tickGems() {
        let collect2 = Balance.gemCollectRadius * Balance.gemCollectRadius
        let magnetR = Balance.magnetRadius * loadout.magnetMultiplier
        let magnet2 = magnetR * magnetR
        for i in gems.indices {
            var g = gems[i]
            guard g.xp > 0 else { continue }
            let d2 = g.pos.distanceSquared(to: player.pos)
            if g.magnetized || d2 < magnet2 {
                g.magnetized = true
                let dir = (player.pos - g.pos).normalized
                g.pos += dir * (Balance.magnetPullSpeed * Balance.dt)
            }
            if d2 < collect2 {
                gainXP(g.xp)
                events.append(.gemCollected(g.pos))
                g.xp = 0   // marks collected; swept below
            }
            gems[i] = g
        }
    }

    private mutating func gainXP(_ amount: Float) {
        player.xp += amount * loadout.xpMultiplier
        while player.xp >= Balance.xpToNext(level: player.level) {
            player.xp -= Balance.xpToNext(level: player.level)
            player.level += 1
            events.append(.leveledUp(player.level))
            if pendingDraft == nil {
                generateDraft(rare: false)
                if pendingDraft != nil { events.append(.draftOpened) }
            } else {
                queuedLevelUps += 1
            }
        }
    }

    // MARK: - Sweeps (single compaction pass per pool per tick)

    private mutating func sweepDead() {
        var i = 0
        while i < enemies.count {
            if enemies[i].hp <= 0 {
                let e = enemies[i]
                kills += 1
                events.append(.enemyDied(e.pos, e.kind))
                dropGem(at: e.pos, xp: Balance.stats(for: e.kind).xp)
                if e.kind == .splitter {
                    spawnSplitChildren(at: e.pos)
                }
                enemies.swapAt(i, enemies.count - 1)
                enemies.removeLast()
            } else {
                i += 1
            }
        }
        i = 0
        while i < projectiles.count {
            if projectiles[i].life <= 0 {
                projectiles.swapAt(i, projectiles.count - 1)
                projectiles.removeLast()
            } else {
                i += 1
            }
        }
        i = 0
        while i < gems.count {
            if gems[i].xp <= 0 {
                gems.swapAt(i, gems.count - 1)
                gems.removeLast()
            } else {
                i += 1
            }
        }
    }

    private mutating func dropGem(at pos: Vec2, xp: Float) {
        if gems.count >= Balance.gemCap {
            // Overflow policy (GOAL §5): merge into the oldest gem.
            gems[0].xp += xp
            return
        }
        gems.append(Gem(pos: pos, xp: xp, magnetized: false))
    }

    private mutating func spawnSplitChildren(at pos: Vec2) {
        for k in 0..<2 {
            guard enemies.count < Balance.enemyCap else { return }
            let stats = Balance.stats(for: .dart)
            let a = rng.float(in: 0...(2 * Float.pi))
            let offset = Vec2(cosApprox(a), sinApprox(a)) * 14
            var child = Enemy(kind: .dart, pos: pos + offset,
                              hp: stats.hp * Balance.hpScale(at: time),
                              radius: stats.radius,
                              phase: rng.float(in: 0...(2 * Float.pi)) + Float(k))
            child.knock = offset.normalized * 120   // burst apart on split
            enemies.append(child)
        }
    }

    // MARK: - Director v1

    private mutating func tickDirector() {
        spawnAccumulator += Balance.spawnRate(at: time) * Balance.dt
        while spawnAccumulator >= 1 {
            spawnAccumulator -= 1
            spawnDirectorEnemy()
        }
    }

    private mutating func spawnDirectorEnemy() {
        guard enemies.count < Balance.enemyCap else {
            // Overflow policy (GOAL §5): cull the farthest enemy first.
            var far = -1
            var farD2: Float = -1
            for (i, e) in enemies.enumerated() {
                let d2 = e.pos.distanceSquared(to: player.pos)
                if d2 > farD2 {
                    farD2 = d2
                    far = i
                }
            }
            if far >= 0 {
                enemies.swapAt(far, enemies.count - 1)
                enemies.removeLast()
            }
            return
        }

        // Weighted kind pick.
        let weights = Balance.spawnWeights(at: time)
        var total: Float = 0
        for w in weights { total += w.1 }
        var roll = rng.unitFloat() * total
        var kind = EnemyKind.dart
        for w in weights {
            roll -= w.1
            if roll <= 0 {
                kind = w.0
                break
            }
        }

        // Ring position just off-screen; re-roll once if too close to the
        // player's heading (GOAL §3 fairness).
        let half = config.viewHalf
        let ringRadius = (half.x * half.x + half.y * half.y).squareRoot() + Balance.spawnMargin
        var angle = rng.float(in: 0...(2 * Float.pi))
        let headingAngle = atan2Approx(player.facing.y, player.facing.x)
        var delta = abs(angleDiff(angle, headingAngle))
        let exclusionHalfAngle = Balance.spawnHeadingExclusion / ringRadius
        if delta < exclusionHalfAngle {
            angle = rng.float(in: 0...(2 * Float.pi))
            delta = abs(angleDiff(angle, headingAngle))
        }
        let pos = player.pos + Vec2(cosApprox(angle), sinApprox(angle)) * ringRadius

        let stats = Balance.stats(for: kind)
        enemies.append(Enemy(kind: kind, pos: pos,
                             hp: stats.hp * Balance.hpScale(at: time),
                             radius: stats.radius,
                             phase: rng.float(in: 0...(2 * Float.pi))))
    }

    // MARK: - Test hooks

    /// Appends an enemy directly (test/demo harnesses only).
    internal mutating func testAppendEnemy(_ e: Enemy) {
        guard enemies.count < Balance.enemyCap else { return }
        enemies.append(e)
    }

    /// Drops a magnetized gem on the player (test harnesses only).
    internal mutating func testDropGem(xp: Float) {
        gems.append(Gem(pos: player.pos, xp: xp, magnetized: true))
    }

    /// Teleports every enemy into a tight clump (worst-case separation load).
    internal mutating func debugClump(at p: Vec2) {
        for i in enemies.indices {
            let jx = rng.float(in: -4...4)
            let jy = rng.float(in: -4...4)
            enemies[i].pos = Vec2(p.x + jx, p.y + jy)
        }
    }

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
        mix(UInt64(player.xp.bitPattern))
        mix(UInt64(player.level))
        mix(UInt64(kills))
        for l in loadout.weaponLevels { mix(UInt64(l)) }
        for l in loadout.passiveLevels { mix(UInt64(l)) }
        mix(UInt64(orbitAngle.bitPattern))
        mix(UInt64(beamAngle.bitPattern))
        for e in enemies {
            mix(UInt64(e.kind.rawValue))
            mix(UInt64(e.pos.x.bitPattern))
            mix(UInt64(e.pos.y.bitPattern))
            mix(UInt64(e.hp.bitPattern))
        }
        for p in projectiles {
            mix(UInt64(p.pos.x.bitPattern))
            mix(UInt64(p.pos.y.bitPattern))
        }
        for g in gems {
            mix(UInt64(g.pos.x.bitPattern))
            mix(UInt64(g.xp.bitPattern))
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

/// Deterministic atan2 (max error ~0.01 rad — spawn angles only).
@inlinable public func atan2Approx(_ y: Float, _ x: Float) -> Float {
    if x == 0 && y == 0 { return 0 }
    let ax = abs(x), ay = abs(y)
    let a = min(ax, ay) / max(ax, ay)
    let s = a * a
    var r = ((-0.0464964749 * s + 0.15931422) * s - 0.327622764) * s * a + a
    if ay > ax { r = .pi / 2 - r }
    if x < 0 { r = .pi - r }
    return y < 0 ? -r : r
}

/// Signed smallest difference between two angles.
@inlinable public func angleDiff(_ a: Float, _ b: Float) -> Float {
    var d = (a - b).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return d
}
