/// Headless play policies for balance simulation (GOAL §4 Balance targets).
/// Bots live in Core (not tests) so future tuning tools can reuse them.
public protocol BotPolicy {
    mutating func move(world: World) -> Vec2
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

/// Competent player proxy: flees the local threat centroid, with a slight
/// orbit bias so it circles the horde instead of running to infinity.
public struct KitingBot: BotPolicy {
    private var rng: SplitMix64

    public init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
    }

    public mutating func move(world: World) -> Vec2 {
        var threat = Vec2.zero
        var weight: Float = 0
        for e in world.enemies {
            let d2 = max(e.pos.distanceSquared(to: world.player.pos), 100)
            guard d2 < 350 * 350 else { continue }
            let w = 1.0 / d2
            threat += (e.pos - world.player.pos) * w
            weight += w
        }
        guard weight > 0 else {
            return .zero   // nothing near — stand and shoot
        }
        let away = (threat * (-1 / weight)).normalized
        // Perpendicular bias → orbiting motion (better gem pickup).
        let orbit = Vec2(-away.y, away.x)
        return (away * 0.85 + orbit * 0.5).normalized
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
public func simulateRun(seed: UInt64, policy: BotPolicy, maxTicks: Int = 36_000) -> RunResult {
    var world = World(seed: seed)
    var bot = policy
    var tick = 0
    while tick < maxTicks, world.state == .playing {
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
