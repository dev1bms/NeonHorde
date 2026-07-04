import Foundation

/// Persistent progression (GOAL §4 Meta): shards, permanent upgrades,
/// cosmetics, Overdrive tiers, stats, settings. Codable → SaveStore.
public enum MetaUpgradeKind: Int, CaseIterable, Codable {
    case maxHP, damage, moveSpeed, magnet, startLevel, revive, shardGain

    public var displayName: String {
        switch self {
        case .maxHP: return "REACTOR CORE"
        case .damage: return "AMPLIFIER"
        case .moveSpeed: return "THRUSTERS"
        case .magnet: return "GRAVITON"
        case .startLevel: return "HEAD START"
        case .revive: return "PHOENIX CELL"
        case .shardGain: return "PROSPECTOR"
        }
    }

    public var blurb: String {
        switch self {
        case .maxHP: return "+15 max HP per rank"
        case .damage: return "+8% damage per rank"
        case .moveSpeed: return "+4% move speed per rank"
        case .magnet: return "+20% pickup radius per rank"
        case .startLevel: return "Start each run 1 level up"
        case .revive: return "Revive once per run"
        case .shardGain: return "+20% shards per rank"
        }
    }

    public var maxRank: Int {
        switch self {
        case .startLevel: return 3
        case .revive: return 1
        default: return 5
        }
    }

    /// Cost of buying the NEXT rank when `rank` ranks are already owned.
    public func cost(rank: Int) -> Int {
        let base: Int
        switch self {
        case .maxHP: base = 40
        case .damage: base = 60
        case .moveSpeed: base = 50
        case .magnet: base = 35
        case .startLevel: base = 120
        case .revive: base = 300
        case .shardGain: base = 80
        }
        return base * (rank + 1) * (rank + 1)   // quadratic escalation
    }
}

public struct MetaState: Codable, Equatable {
    public var schemaVersion = 1
    public var shards = 0
    public var upgradeRanks = [Int](repeating: 0, count: MetaUpgradeKind.allCases.count)
    public var selectedShape = 0            // 0 circle, 1 triangle, 2 star, 3 hex
    public var unlockedShapes = [0]
    public var selectedTrail = 0            // palette index
    public var unlockedTrails = [0]
    public var highestOverdriveBeaten = -1  // -1 = base game not yet beaten
    public var bestSurvivalSeconds: Float = 0
    public var bestKills = 0
    public var totalRuns = 0
    public var victories = 0
    public var musicOn = true
    public var sfxOn = true
    public var hapticsOn = true

    public init() {}

    public func rank(of kind: MetaUpgradeKind) -> Int {
        upgradeRanks[kind.rawValue]
    }

    public var maxOverdriveTier: Int { 5 }
    /// Tiers selectable on the pre-run screen (0 = base).
    public var unlockedOverdriveTier: Int {
        min(highestOverdriveBeaten + 1, maxOverdriveTier)
    }

    public mutating func buy(_ kind: MetaUpgradeKind) -> Bool {
        let r = rank(of: kind)
        guard r < kind.maxRank else { return false }
        let price = kind.cost(rank: r)
        guard shards >= price else { return false }
        shards -= price
        upgradeRanks[kind.rawValue] = r + 1
        return true
    }

    // MARK: Derived run bonuses (consumed by World.init)

    public var bonusMaxHP: Float { 15 * Float(rank(of: .maxHP)) }
    public var damageMultiplier: Float { 1 + 0.08 * Float(rank(of: .damage)) }
    public var speedMultiplier: Float { 1 + 0.04 * Float(rank(of: .moveSpeed)) }
    public var magnetMultiplier: Float { 1 + 0.20 * Float(rank(of: .magnet)) }
    public var startLevels: Int { rank(of: .startLevel) }
    public var revives: Int { rank(of: .revive) }
    public var shardMultiplier: Float { 1 + 0.20 * Float(rank(of: .shardGain)) }
}

/// Overdrive tier modifiers (GOAL §4): selected pre-run after first victory.
public enum Overdrive {
    public static func enemyHPMult(tier: Int) -> Float { 1 + 0.35 * Float(tier) }
    public static func enemySpeedMult(tier: Int) -> Float { 1 + 0.06 * Float(tier) }
    public static func spawnRateMult(tier: Int) -> Float { 1 + 0.15 * Float(tier) }
    public static func shardMult(tier: Int) -> Float { 1 + 0.25 * Float(tier) }
}
