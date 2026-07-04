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
    public static let magnetRadius: Float = 70

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
}
