/// PRIME — the three-phase boss (GOAL §4). The run is WON the moment it dies;
/// at 10:30 it enrages (+3%/s compounding) so fights cannot stall.
public struct Boss {
    public enum Phase: Int {
        case charge = 1     // hp > 66%: telegraphed dashes
        case barrage = 2    // 33–66%: radial rings + minion spawns
        case storm = 3      // < 33%: spinning beam sweeps
    }

    public var pos: Vec2
    public var vel: Vec2 = .zero
    public var hp: Float
    public var maxHP: Float
    public var spinAngle: Float = 0
    public var attackTimer: Float = 2.5
    public var chargeState: Int = 0        // 0 idle, 1 telegraph, 2 dashing
    public var chargeDir: Vec2 = .zero

    public var phase: Phase {
        let f = hp / maxHP
        if f > 0.66 { return .charge }
        if f > 0.33 { return .barrage }
        return .storm
    }

    init(pos: Vec2) {
        self.pos = pos
        self.hp = Balance.bossHP
        self.maxHP = Balance.bossHP
    }
}

extension World {
    mutating func spawnBoss() {
        // The arena clears for the finale: every field enemy dies in a gem
        // shower (splitters don't split during the wipe).
        wipeInProgress = true
        for i in enemies.indices {
            enemies[i].hp = -1
        }
        enemyShots.removeAll(keepingCapacity: true)   // clean slate for the duel
        let half = config.viewHalf
        let ringRadius = (half.x * half.x + half.y * half.y).squareRoot() + 120
        let a = rng.float(in: 0...(2 * Float.pi))
        boss = Boss(pos: player.pos + Vec2(cosApprox(a), sinApprox(a)) * ringRadius)
        events.append(.bossSpawned)
    }

    mutating func tickBoss() {
        guard var b = boss else { return }
        let enrage = Balance.enrageMultiplier(secondsPastEnrage: time - Balance.bossEnrageTime)
        let lastPhase = b.phase

        // Movement + phase behaviors
        b.spinAngle += (b.phase == .storm ? 1.4 : 0.5) * Balance.dt
        b.attackTimer -= Balance.dt
        let toPlayer = (player.pos - b.pos).normalized

        switch b.phase {
        case .charge:
            switch b.chargeState {
            case 1:   // telegraph: slow crawl, then commit
                b.vel = b.chargeDir * 30
                if b.attackTimer <= 0 {
                    b.chargeState = 2
                    b.attackTimer = 1.1
                }
            case 2:   // dash
                b.vel = b.chargeDir * (Balance.bossChargeSpeed * enrage)
                if b.attackTimer <= 0 {
                    b.chargeState = 0
                    b.attackTimer = 1.6
                }
            default:  // approach, then wind up a dash
                b.vel = toPlayer * (Balance.bossBaseSpeed * enrage)
                if b.attackTimer <= 0 {
                    b.chargeState = 1
                    b.chargeDir = toPlayer
                    b.attackTimer = 0.55
                }
            }
        case .barrage:
            b.vel = toPlayer * (Balance.bossBaseSpeed * 0.8 * enrage)
            if b.attackTimer <= 0 {
                b.attackTimer = Balance.bossRingCooldown / enrage
                fireBossRing(from: b.pos, count: Balance.bossRingCount, enrage: enrage)
                spawnBossMinions(around: b.pos)
            }
        case .storm:
            b.vel = toPlayer * (Balance.bossBaseSpeed * 0.6 * enrage)
            // Continuous twin beam sweep damage (corridor vs player).
            let dps = Balance.bossBeamDPS * enrage
            for k in 0..<2 {
                let a = b.spinAngle + Float(k) * .pi
                let dir = Vec2(cosApprox(a), sinApprox(a))
                let rel = player.pos - b.pos
                let along = rel.x * dir.x + rel.y * dir.y
                let perp = abs(rel.x * dir.y - rel.y * dir.x)
                if along > 0, along < 700,
                   perp < Balance.bossBeamHalfWidth + Balance.playerRadius,
                   !config.playerInvulnerable {
                    player.hp -= dps * Balance.dt   // beams bypass i-frames (dodge them!)
                }
            }
            if b.attackTimer <= 0 {
                b.attackTimer = 3.0 / enrage
                fireBossRing(from: b.pos, count: 10, enrage: enrage)
            }
        }

        b.pos += b.vel * Balance.dt

        // Contact with player (hard ring + damage through the normal path).
        let rr = Balance.bossRadius + Balance.playerRadius
        if b.pos.distanceSquared(to: player.pos) < rr * rr {
            if player.iFrames <= 0, !config.playerInvulnerable {
                player.hp -= max(1, Balance.bossContactDamage * enrage - loadout.flatArmor)
                player.iFrames = Balance.playerIFrames
                events.append(.playerHit(Balance.bossContactDamage))
            }
            let d = max(b.pos.distanceSquared(to: player.pos).squareRoot(), 1)
            player.pos = b.pos + (player.pos - b.pos) * (rr / d)
        }

        // Player projectiles vs boss (boss is not in the enemy hash).
        for i in projectiles.indices {
            var p = projectiles[i]
            guard p.life > 0, !p.mine else { continue }
            let hit = Balance.bossRadius + p.radius
            if p.pos.distanceSquared(to: b.pos) <= hit * hit {
                b.hp -= p.damage
                if p.pierce > 0 { p.pierce -= 1 } else { p.life = 0 }
                projectiles[i] = p
            }
        }
        // Continuous player weapons vs boss.
        bossTakeContinuousDamage(&b)

        if b.phase != lastPhase {
            events.append(.bossPhase(b.phase.rawValue))
        }

        if b.hp <= 0 {
            boss = nil
            kills += 1
            shardDrops += Balance.bossShards
            state = .victory
            events.append(.bossDied)
        } else {
            boss = b
        }
    }

    private mutating func bossTakeContinuousDamage(_ b: inout Boss) {
        // Orbit blades
        let bladeLevel = loadout.level(of: .orbitBlades)
        if bladeLevel > 0 {
            let p = Balance.weapon(.orbitBlades, level: bladeLevel, loadout: loadout)
            for k in 0..<p.count {
                let a = orbitAngle + Float(k) * (2 * .pi / Float(p.count))
                let bladePos = player.pos + Vec2(cosApprox(a), sinApprox(a)) * p.area
                let rr = 18 + Balance.bossRadius
                if bladePos.distanceSquared(to: b.pos) <= rr * rr {
                    b.hp -= p.damage * Balance.dt
                }
            }
        }
        // Prism beam
        let beamLevel = loadout.level(of: .prismBeam)
        if beamLevel > 0 {
            let p = Balance.weapon(.prismBeam, level: beamLevel, loadout: loadout)
            for k in 0..<p.count {
                let a = beamAngle + Float(k) * .pi
                let dir = Vec2(cosApprox(a), sinApprox(a))
                let rel = b.pos - player.pos
                let along = rel.x * dir.x + rel.y * dir.y
                let perp = abs(rel.x * dir.y - rel.y * dir.x)
                if along > 0, along < 500, perp < p.area + Balance.bossRadius {
                    b.hp -= p.damage * Balance.dt
                }
            }
        }
        // Nova/rail/chain hit the boss through their fire paths? Those target
        // the enemies array — give them boss splash here: nova radius check on fire
        // is handled via bossNovaSplash flag set by fireNovaBurst… simpler: nova
        // splash applied when event fired this tick.
        for event in events {
            if case .novaBurst(let center, let radius) = event {
                let rr = radius + Balance.bossRadius
                if center.distanceSquared(to: b.pos) <= rr * rr {
                    let lv = loadout.level(of: .novaBurst)
                    let p = Balance.weapon(.novaBurst, level: max(1, lv), loadout: loadout)
                    b.hp -= p.damage
                }
            }
            if case .railLance(let origin, let dir, let length) = event {
                let rel = b.pos - origin
                let along = rel.x * dir.x + rel.y * dir.y
                let perp = abs(rel.x * dir.y - rel.y * dir.x)
                let lv = loadout.level(of: .railLance)
                let p = Balance.weapon(.railLance, level: max(1, lv), loadout: loadout)
                if along > 0, along < length, perp < p.area + Balance.bossRadius {
                    b.hp -= p.damage
                }
            }
        }
    }

    private mutating func fireBossRing(from pos: Vec2, count: Int, enrage: Float) {
        for i in 0..<count {
            guard enemyShots.count < Balance.enemyShotCap else { break }
            let a = Float(i) / Float(count) * 2 * .pi + spinOffsetForRing()
            enemyShots.append(Projectile(pos: pos,
                                         vel: Vec2(cosApprox(a), sinApprox(a)) * (Balance.bossShotSpeed * enrage),
                                         damage: Balance.bossShotDamage, radius: Balance.enemyShotRadius,
                                         life: Balance.enemyShotLife, pierce: 0))
        }
    }

    private mutating func spinOffsetForRing() -> Float {
        rng.float(in: 0...(2 * Float.pi / 14))
    }

    private mutating func spawnBossMinions(around pos: Vec2) {
        for _ in 0..<4 {
            guard enemies.count < Balance.enemyCap else { return }
            let a = rng.float(in: 0...(2 * Float.pi))
            let stats = Balance.stats(for: .dart)
            enemies.append(Enemy(kind: .dart, pos: pos + Vec2(cosApprox(a), sinApprox(a)) * 70,
                                 hp: stats.hp * Balance.hpScale(at: time),
                                 radius: stats.radius,
                                 phase: rng.float(in: 0...(2 * Float.pi))))
        }
    }
}
