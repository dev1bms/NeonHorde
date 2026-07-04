/// ALL tunable numbers live here (GOAL §4/§5). Tune here only.
public enum Balance {
    // MARK: Simulation
    public static let tickRate: Float = 60
    public static let dt: Float = 1.0 / 60.0

    // MARK: Pools (hard caps — overflow policies in World)
    public static let enemyCap = 600
    public static let projectileCap = 400
    public static let gemCap = 300
    public static let damageNumberCap = 60

    // MARK: Spatial hash
    public static let cellSize: Float = 64

    // MARK: Player
    public static let playerRadius: Float = 14
    public static let playerSpeed: Float = 190          // pt/s
    public static let playerMaxHP: Float = 100
    public static let playerIFrames: Float = 0.5        // seconds
    public static let magnetRadius: Float = 90

    // MARK: Enemies (base stats; Director scales HP over the timeline)
    public struct EnemyStats {
        public let hp: Float
        public let speed: Float
        public let radius: Float
        public let contactDamage: Float
        public let xp: Float
        public let threat: Float    // 0..1, drives the magenta→orange color ramp

        public init(hp: Float, speed: Float, radius: Float,
                    contactDamage: Float, xp: Float, threat: Float) {
            self.hp = hp
            self.speed = speed
            self.radius = radius
            self.contactDamage = contactDamage
            self.xp = xp
            self.threat = threat
        }
    }

    public static func stats(for kind: EnemyKind) -> EnemyStats {
        switch kind {
        case .dart:     return EnemyStats(hp: 8,   speed: 120, radius: 10, contactDamage: 6,  xp: 1, threat: 0.0)
        case .brick:    return EnemyStats(hp: 45,  speed: 45,  radius: 16, contactDamage: 12, xp: 3, threat: 0.35)
        case .splitter: return EnemyStats(hp: 22,  speed: 75,  radius: 13, contactDamage: 8,  xp: 2, threat: 0.55)
        case .weaver:   return EnemyStats(hp: 14,  speed: 105, radius: 11, contactDamage: 8,  xp: 2, threat: 0.75)
        case .spitter:  return EnemyStats(hp: 18,  speed: 60,  radius: 13, contactDamage: 8,  xp: 3, threat: 1.0)
        }
    }

    // MARK: Enemy behavior
    public static let enemySeparationRadius: Float = 22
    public static let enemySeparationPush: Float = 60   // pt/s of push at full overlap
    public static let separationNeighborCap = 8         // dense-clump O(n²) guard
    public static let spawnMargin: Float = 60           // pt beyond screen half-diagonal
    public static let spawnHeadingExclusion: Float = 150 // never spawn this close to player heading (GOAL §3)
    public static let contactKnockback: Float = 90      // pt/s impulse pushing enemy off the player

    // MARK: Pulse Bolt (starter weapon; full tables arrive in Phase 4)
    public static let boltCooldown: Float = 0.45        // seconds between shots
    public static let boltDamage: Float = 10            // one-shots a base dart
    public static let boltSpeed: Float = 420
    public static let boltRadius: Float = 5
    public static let boltLifetime: Float = 1.6
    public static let boltRange: Float = 480            // max target acquisition distance

    // MARK: XP / leveling
    public static let gemCollectRadius: Float = 22
    public static let magnetPullSpeed: Float = 420
    /// XP required to advance FROM the given level (1-based).
    public static func xpToNext(level: Int) -> Float {
        4 + Float(level - 1) * 3
    }

    // MARK: Run timeline (GOAL §4: elites 2:30/5:00/7:30, boss 9:00,
    // spawns stop 9:30, enrage 10:30, win = PRIME dies)
    public static let eliteTimes: [Float] = [150, 300, 450]
    public static let eliteHPMultiplier: Float = 22
    public static let eliteContactMultiplier: Float = 2
    public static let eliteSpeedMultiplier: Float = 0.75
    public static let eliteScale: Float = 2.5
    public static let bossSpawnTime: Float = 540
    public static let spawnsStopTime: Float = 570
    public static let bossEnrageTime: Float = 630
    /// Enrage: damage & speed +3%/s compounding (multiplier = 1.03^seconds).
    public static func enrageMultiplier(secondsPastEnrage t: Float) -> Float {
        guard t > 0 else { return 1 }
        // 1.03^t via exp-free powf approximation: (1.03)^t = e^(t·ln1.03),
        // computed with a short series good to ±1% over 0..300s.
        let x = t * 0.029558802   // ln(1.03)
        var result: Float = 1
        var term: Float = 1
        for k in 1...8 {
            term *= x / Float(k)
            result += term
        }
        return result
    }

    // MARK: PRIME boss
    public static let bossHP: Float = 5200
    public static let bossRadius: Float = 46
    public static let bossContactDamage: Float = 22
    public static let bossBaseSpeed: Float = 60
    public static let bossChargeSpeed: Float = 330
    public static let bossShotDamage: Float = 9
    public static let bossShotSpeed: Float = 150
    public static let bossRingCount = 10
    public static let bossRingCooldown: Float = 2.6
    public static let bossBeamDPS: Float = 30
    public static let bossBeamHalfWidth: Float = 14
    public static let bossXP: Float = 0          // boss drops victory, not gems
    public static let bossShards = 150

    // MARK: Enemy ranged shots (spitter + boss rings)
    public static let spitterShotDamage: Float = 7
    public static let spitterShotSpeed: Float = 130
    public static let spitterShotCooldown: Float = 3.2
    public static let enemyShotRadius: Float = 6
    public static let enemyShotLife: Float = 3.5
    public static let enemyShotCap = 120

    // MARK: Chests
    public static let chestCollectRadius: Float = 30

    // MARK: Director v1 (escalating spawn timeline; retuned in Phase 5)
    /// Spawns per second at time t. Gentle early (power fantasy builds); a
    /// mild squeeze after 5:00 keeps pressure honest — PRIME (9:00) is the
    /// run-ender now, not attrition.
    public static func spawnRate(at t: Float) -> Float {
        let base = 0.8 + t * 0.02           // ~0.8/s at start → ~7/s at 5:00
        let lateSqueeze = t > 300 ? (t - 300) * 0.015 : 0
        return base + lateSqueeze           // ~10/s at 7:00, ~14/s at 9:00
    }
    /// Enemy HP multiplier over the run (mild late acceleration — the boss,
    /// not attrition, ends runs since Phase 5).
    public static func hpScale(at t: Float) -> Float {
        let late = t > 300 ? (t - 300) / 240 : 0
        return 1 + t / 180 + late
    }
    /// Kind mix weights over time (dart-heavy early, mixed later).
    public static func spawnWeights(at t: Float) -> [(EnemyKind, Float)] {
        [
            (.dart, 10),
            (.brick, t > 25 ? 3 : 0),
            (.splitter, t > 45 ? 3 : 0),
            (.weaver, t > 70 ? 4 : 0),
            (.spitter, t > 100 ? 3 : 0),
        ]
    }
}
