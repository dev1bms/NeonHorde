/// All eight weapon systems (GOAL §4). Table damage is per-hit for discrete
/// weapons and per-second for continuous ones (orbit blades, prism beam).
extension World {
    mutating func tickWeaponSystems() {
        for kind in WeaponKind.allCases {
            let level = loadout.level(of: kind)
            guard level > 0 else { continue }
            let params = Balance.weapon(kind, level: level, loadout: loadout)

            switch kind {
            case .orbitBlades:
                tickOrbitBlades(params)
            case .prismBeam:
                tickPrismBeam(params)
            default:
                weaponCooldowns[kind.rawValue] -= Balance.dt
                if weaponCooldowns[kind.rawValue] <= 0 {
                    if fire(kind, params) {
                        weaponCooldowns[kind.rawValue] = params.cooldown
                    } else {
                        weaponCooldowns[kind.rawValue] = 0.1   // no target — retry soon
                    }
                }
            }
        }
    }

    /// Returns false when there was nothing to shoot at.
    private mutating func fire(_ kind: WeaponKind, _ p: WeaponParams) -> Bool {
        switch kind {
        case .pulseBolt: return firePulseBolt(p)
        case .novaBurst: return fireNovaBurst(p)
        case .railLance: return fireRailLance(p)
        case .chainArc: return fireChainArc(p)
        case .seekerSwarm: return fireSeekerSwarm(p)
        case .mineField: return fireMineField(p)
        case .orbitBlades, .prismBeam: return true
        }
    }

    // MARK: Discrete weapons

    private mutating func firePulseBolt(_ p: WeaponParams) -> Bool {
        guard let dir = directionToNearestEnemy(maxDistance: Balance.boltRange) else { return false }
        let baseAngle = atan2Approx(dir.y, dir.x)
        for i in 0..<p.count {
            guard projectiles.count < Balance.projectileCap else { break }
            let spread = p.count == 1 ? 0 : (Float(i) - Float(p.count - 1) / 2) * 0.16
            let a = baseAngle + spread
            projectiles.append(Projectile(pos: player.pos,
                                          vel: Vec2(cosApprox(a), sinApprox(a)) * p.speed,
                                          damage: p.damage, radius: Balance.boltRadius,
                                          life: Balance.boltLifetime, pierce: p.pierce))
        }
        return true
    }

    private mutating func fireNovaBurst(_ p: WeaponParams) -> Bool {
        var hitAny = false
        for i in enemies.indices
        where enemies[i].pos.distanceSquared(to: player.pos) <= p.area * p.area {
            enemies[i].hp -= p.damage
            hitAny = true
        }
        guard hitAny else { return false }
        events.append(.novaBurst(player.pos, p.area))
        return true
    }

    private mutating func fireRailLance(_ p: WeaponParams) -> Bool {
        guard !enemies.isEmpty else { return false }
        let length: Float = 600
        // Pick the densest of 12 sampled directions.
        var bestAngle: Float = 0
        var bestCount = 0
        for s in 0..<12 {
            let a = Float(s) * (.pi / 6)
            let dir = Vec2(cosApprox(a), sinApprox(a))
            var count = 0
            for e in enemies {
                let rel = e.pos - player.pos
                let along = rel.x * dir.x + rel.y * dir.y
                guard along > 0, along < length else { continue }
                let perp = abs(rel.x * dir.y - rel.y * dir.x)
                if perp < p.area + e.radius { count += 1 }
            }
            if count > bestCount {
                bestCount = count
                bestAngle = a
            }
        }
        guard bestCount > 0 else { return false }
        let dir = Vec2(cosApprox(bestAngle), sinApprox(bestAngle))
        for i in enemies.indices {
            let rel = enemies[i].pos - player.pos
            let along = rel.x * dir.x + rel.y * dir.y
            guard along > 0, along < length else { continue }
            let perp = abs(rel.x * dir.y - rel.y * dir.x)
            if perp < p.area + enemies[i].radius {
                enemies[i].hp -= p.damage
            }
        }
        events.append(.railLance(player.pos, dir, length))
        return true
    }

    private mutating func fireChainArc(_ p: WeaponParams) -> Bool {
        guard let first = nearestEnemyIndex(to: player.pos, maxDistance: 300) else { return false }
        var chainPoints: [Vec2] = [player.pos]
        var visited: [Int] = []
        var current = first
        for _ in 0..<p.count {
            enemies[current].hp -= p.damage
            visited.append(current)
            chainPoints.append(enemies[current].pos)
            // Next: nearest unvisited living enemy within jump range.
            var next = -1
            var bestD2 = p.area * p.area
            for (i, e) in enemies.enumerated()
            where e.hp > 0 && !visited.contains(i) {
                let d2 = e.pos.distanceSquared(to: enemies[current].pos)
                if d2 < bestD2 {
                    bestD2 = d2
                    next = i
                }
            }
            if next < 0 { break }
            current = next
        }
        events.append(.chainArc(chainPoints))
        return true
    }

    private mutating func fireSeekerSwarm(_ p: WeaponParams) -> Bool {
        guard !enemies.isEmpty else { return false }
        for i in 0..<p.count {
            guard projectiles.count < Balance.projectileCap else { break }
            let a = rng.float(in: 0...(2 * Float.pi)) + Float(i)
            var proj = Projectile(pos: player.pos,
                                  vel: Vec2(cosApprox(a), sinApprox(a)) * p.speed,
                                  damage: p.damage, radius: 6, life: 3.0, pierce: 0)
            proj.homing = true
            projectiles.append(proj)
        }
        return true
    }

    private mutating func fireMineField(_ p: WeaponParams) -> Bool {
        for _ in 0..<p.count {
            guard projectiles.count < Balance.projectileCap else { break }
            let a = rng.float(in: 0...(2 * Float.pi))
            let offset = Vec2(cosApprox(a), sinApprox(a)) * rng.float(in: 14...40)
            var mine = Projectile(pos: player.pos + offset, vel: .zero,
                                  damage: p.damage, radius: 9, life: 10, pierce: 0)
            mine.mine = true
            mine.aoe = p.area
            projectiles.append(mine)
        }
        return true
    }

    // MARK: Continuous weapons (damage = DPS)

    private mutating func tickOrbitBlades(_ p: WeaponParams) {
        orbitAngle += p.speed * Balance.dt
        let dps = p.damage
        for k in 0..<p.count {
            let a = orbitAngle + Float(k) * (2 * .pi / Float(p.count))
            let bladePos = player.pos + Vec2(cosApprox(a), sinApprox(a)) * p.area
            var hits: [Int32] = []
            enemyHash.forEachNeighbor(x: bladePos.x, y: bladePos.y, radius: 36) { id, _, _ in
                hits.append(id)
            }
            for id in hits {
                let i = Int(id)
                let rr = 18 + enemies[i].radius
                if enemies[i].pos.distanceSquared(to: bladePos) <= rr * rr {
                    enemies[i].hp -= dps * Balance.dt
                }
            }
        }
    }

    private mutating func tickPrismBeam(_ p: WeaponParams) {
        beamAngle += p.speed * Balance.dt
        let dps = p.damage
        let length: Float = 500
        for k in 0..<p.count {
            let a = beamAngle + Float(k) * .pi
            let dir = Vec2(cosApprox(a), sinApprox(a))
            for i in enemies.indices {
                let rel = enemies[i].pos - player.pos
                let along = rel.x * dir.x + rel.y * dir.y
                guard along > 0, along < length else { continue }
                let perp = abs(rel.x * dir.y - rel.y * dir.x)
                if perp < p.area + enemies[i].radius {
                    enemies[i].hp -= dps * Balance.dt
                }
            }
        }
    }

    // MARK: Targeting helpers

    func nearestEnemyIndex(to pos: Vec2, maxDistance: Float) -> Int? {
        var best = -1
        var bestD2 = maxDistance * maxDistance
        for (i, e) in enemies.enumerated() where e.hp > 0 {
            let d2 = e.pos.distanceSquared(to: pos)
            if d2 < bestD2 {
                bestD2 = d2
                best = i
            }
        }
        return best >= 0 ? best : nil
    }

    func directionToNearestEnemy(maxDistance: Float) -> Vec2? {
        guard let i = nearestEnemyIndex(to: player.pos, maxDistance: maxDistance) else { return nil }
        return (enemies[i].pos - player.pos).normalized
    }
}
