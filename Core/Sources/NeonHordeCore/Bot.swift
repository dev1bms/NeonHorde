/// Headless play policies for balance simulation (GOAL §4 Balance targets).
/// Bots live in Core (not tests) so future tuning tools can reuse them.
public protocol BotPolicy {
    mutating func move(world: World) -> Vec2
    /// Returns the draft card index to pick. Default: sensible-player heuristic.
    mutating func pickDraft(_ draft: Draft, world: World) -> Int
}

public extension BotPolicy {
    /// "Sensible player" heuristic: grab new weapons until 3 are owned, then
    /// level owned weapons, then damage-flavored passives.
    mutating func pickDraft(_ draft: Draft, world: World) -> Int {
        func score(_ c: UpgradeChoice) -> Int {
            switch c {
            case .weapon(let w):
                let owned = world.loadout.level(of: w) > 0
                if !owned && world.loadout.ownedWeaponCount < 3 { return 100 }
                return owned ? 80 : 40
            case .passive(let p):
                switch p {
                case .damage, .cooldown, .projectileCount: return 60
                case .maxHP, .armor: return 50
                default: return 30
                }
            }
        }
        var best = 0
        var bestScore = -1
        for (i, c) in draft.choices.enumerated() where score(c) > bestScore {
            bestScore = score(c)
            best = i
        }
        return best
    }
}

/// Baseline "fresh player": drifts in a random direction, re-rolling every
/// ~0.7 s. No threat awareness at all.
public struct RandomWalkBot: BotPolicy {
    private var rng: SplitMix64
    private var dir = Vec2(1, 0)
    private var hold = 0

    public init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
    }

    public mutating func move(world: World) -> Vec2 {
        hold -= 1
        if hold <= 0 {
            hold = rng.int(in: 30...55)
            let a = rng.float(in: 0...(2 * Float.pi))
            dir = Vec2(cosApprox(a), sinApprox(a))
        }
        return dir
    }
}

/// Competent player proxy: samples 16 headings, scores each by projected
/// threat density at the lookahead point (plus gem greed and momentum), and
/// commits to the best. A far better skill-ceiling proxy than centroid-flee.
public struct KitingBot: BotPolicy {
    private var rng: SplitMix64
    private var lastDir = Vec2(1, 0)

    public init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
    }

    public mutating func move(world: World) -> Vec2 {
        let p = world.player.pos
        var bestDir = Vec2.zero
        var bestScore = -Float.greatestFiniteMagnitude

        for s in 0..<16 {
            let a = Float(s) / 16 * 2 * .pi
            let dir = Vec2(cosApprox(a), sinApprox(a))
            let probe = p + dir * 90   // where we'd be in ~half a second
            var score: Float = 0

            for e in world.enemies {
                let d2 = max(e.pos.distanceSquared(to: probe), 64)
                if d2 < 320 * 320 {
                    // Anticipate their chase: closing enemies count double.
                    let closing = (e.vel.x * dir.x + e.vel.y * dir.y) < 0 ? 2.0 : 1.0 as Float
                    score -= closing * 9000 / d2
                }
            }
            for shot in world.enemyShots {
                let d2 = max(shot.pos.distanceSquared(to: probe), 64)
                if d2 < 150 * 150 { score -= 6000 / d2 }
            }
            if let b = world.boss {
                // Fight from a band (~330 pt): close enough for every weapon,
                // far enough to react to dashes.
                let d = b.pos.distanceSquared(to: probe).squareRoot()
                let bandError = (d - 330) / 100
                score -= bandError * bandError * 2.5
                if d < 180 { score -= 4000 / max(d * d, 64) }   // hard no-fly zone
                // Storm-phase beams sweep from spinAngle — stay out of both corridors.
                if b.phase == .storm {
                    for k in 0..<2 {
                        let ba = b.spinAngle + Float(k) * .pi + 0.25   // lead the sweep
                        let bd = Vec2(cosApprox(ba), sinApprox(ba))
                        let rel = probe - b.pos
                        let along = rel.x * bd.x + rel.y * bd.y
                        let perp = abs(rel.x * bd.y - rel.y * bd.x)
                        if along > 0, along < 700, perp < 60 {
                            score -= 30
                        }
                    }
                }
            }
            // Gem greed keeps builds coming online — collecting is playing.
            for g in world.gems {
                let d2 = max(g.pos.distanceSquared(to: probe), 100)
                if d2 < 280 * 280 { score += 1100 / d2 }
            }
            // Momentum: avoid dithering.
            score += (dir.x * lastDir.x + dir.y * lastDir.y) * 0.02

            // Home anchor: kite in circles near the origin instead of fleeing
            // to infinity — that's how humans play, and it loops the bot back
            // through its own kill zones to harvest gems.
            if world.boss == nil {
                let homeD = probe.length
                if homeD > 400 {
                    let over = (homeD - 400) / 200
                    score -= over * over
                }
            }

            if score > bestScore {
                bestScore = score
                bestDir = dir
            }
        }

        // If nothing threatens at all, chase gems or stand still.
        if bestScore <= 0.05, bestScore >= -0.05 {
            return .zero
        }
        lastDir = bestDir
        return bestDir
    }
}

public struct RunResult {
    public let deathTick: Int?      // nil = survived to maxTicks
    public let kills: Int
    public let level: Int
    public let survivedSeconds: Float

    public var died: Bool { deathTick != nil }
}

/// Runs a full headless game. ~3–4 orders of magnitude faster than realtime.
/// `declineDrafts` pins the run to the starter weapon (baseline comparisons).
public func simulateRun(seed: UInt64, policy: BotPolicy, maxTicks: Int = 36_000,
                        declineDrafts: Bool = false) -> RunResult {
    var world = World(seed: seed)
    var bot = policy
    var tick = 0
    while tick < maxTicks, world.state == .playing {
        if let draft = world.pendingDraft {
            if declineDrafts {
                world.declineDraft()
            } else {
                world.applyDraft(bot.pickDraft(draft, world: world))
            }
            continue   // draft resolution consumes no simulated time
        }
        world.tick(WorldInput(move: bot.move(world: world)))
        tick += 1
    }
    return RunResult(
        deathTick: world.state == .dead ? tick : nil,
        kills: world.kills,
        level: world.player.level,
        survivedSeconds: Float(tick) * Balance.dt
    )
}
