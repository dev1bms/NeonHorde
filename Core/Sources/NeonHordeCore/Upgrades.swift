/// Weapons, passives, and the level-up draft (GOAL §4).
/// All state lives in fixed arrays indexed by rawValue — never iterate a
/// Dictionary where order affects outcomes (determinism rule, GOAL §5).
public enum WeaponKind: Int, CaseIterable {
    case pulseBolt, orbitBlades, novaBurst, railLance, chainArc, seekerSwarm, mineField, prismBeam

    public var displayName: String {
        switch self {
        case .pulseBolt: return "PULSE BOLT"
        case .orbitBlades: return "ORBIT BLADES"
        case .novaBurst: return "NOVA BURST"
        case .railLance: return "RAIL LANCE"
        case .chainArc: return "CHAIN ARC"
        case .seekerSwarm: return "SEEKER SWARM"
        case .mineField: return "MINE FIELD"
        case .prismBeam: return "PRISM BEAM"
        }
    }
}

public enum PassiveKind: Int, CaseIterable {
    case damage, cooldown, moveSpeed, magnet, maxHP, armor, projectileCount, xpGain

    public var displayName: String {
        switch self {
        case .damage: return "OVERCHARGE"
        case .cooldown: return "RAPID CYCLE"
        case .moveSpeed: return "AFTERBURN"
        case .magnet: return "TRACTOR FIELD"
        case .maxHP: return "BULWARK CORE"
        case .armor: return "PLATING"
        case .projectileCount: return "SPLIT MATRIX"
        case .xpGain: return "RESONANCE"
        }
    }
}

public enum UpgradeChoice: Equatable {
    case weapon(WeaponKind)
    case passive(PassiveKind)

    public var title: String {
        switch self {
        case .weapon(let w): return w.displayName
        case .passive(let p): return p.displayName
        }
    }
}

public struct Loadout {
    public internal(set) var weaponLevels = [Int](repeating: 0, count: WeaponKind.allCases.count)
    public internal(set) var passiveLevels = [Int](repeating: 0, count: PassiveKind.allCases.count)

    public static let maxLevel = 5
    public static let maxWeapons = 4
    public static let maxPassives = 4

    public func level(of w: WeaponKind) -> Int { weaponLevels[w.rawValue] }
    public func level(of p: PassiveKind) -> Int { passiveLevels[p.rawValue] }

    public var ownedWeaponCount: Int { weaponLevels.lazy.filter { $0 > 0 }.count }
    public var ownedPassiveCount: Int { passiveLevels.lazy.filter { $0 > 0 }.count }

    // MARK: Passive-derived multipliers

    public var damageMultiplier: Float { 1 + 0.12 * Float(level(of: .damage)) }
    public var cooldownMultiplier: Float { max(0.5, 1 - 0.07 * Float(level(of: .cooldown))) }
    public var moveSpeedMultiplier: Float { 1 + 0.07 * Float(level(of: .moveSpeed)) }
    public var magnetMultiplier: Float { 1 + 0.30 * Float(level(of: .magnet)) }
    public var bonusMaxHP: Float { 20 * Float(level(of: .maxHP)) }
    public var flatArmor: Float { Float(level(of: .armor)) }
    /// Extra projectiles at SPLIT MATRIX levels 1/3/5.
    public var bonusProjectiles: Int { (level(of: .projectileCount) + 1) / 2 }
    public var xpMultiplier: Float { 1 + 0.10 * Float(level(of: .xpGain)) }
}

/// Resolved per-shot parameters for a weapon at a given level (with passives).
public struct WeaponParams {
    public var damage: Float
    public var cooldown: Float
    public var count: Int        // projectiles / blades / chain jumps
    public var speed: Float
    public var pierce: Int
    public var area: Float       // aoe radius / corridor half-width / orbit radius
}

extension Balance {
    /// Data-driven weapon table (formula form — one place to tune).
    public static func weapon(_ kind: WeaponKind, level: Int, loadout: Loadout) -> WeaponParams {
        let lv = Float(level)
        var p: WeaponParams
        switch kind {
        case .pulseBolt:
            p = WeaponParams(damage: 8 + 4 * lv, cooldown: 0.48 - 0.03 * lv,
                             count: 1 + (level >= 4 ? 1 : 0), speed: 420,
                             pierce: level >= 5 ? 1 : 0, area: 0)
        case .orbitBlades:
            // Orbit sits just outside the contact ring so blades grind the
            // enemies that are actually threatening the player.
            p = WeaponParams(damage: 8 + 4 * lv, cooldown: 0, count: 1 + level,
                             speed: 2.4, pierce: 0, area: 40 + 4 * lv)   // speed = rad/s
        case .novaBurst:
            p = WeaponParams(damage: 12 + 6 * lv, cooldown: 2.6 - 0.22 * lv,
                             count: 1, speed: 0, pierce: 0, area: 95 + 14 * lv)
        case .railLance:
            p = WeaponParams(damage: 16 + 7 * lv, cooldown: 2.0 - 0.15 * lv,
                             count: 1, speed: 0, pierce: 999, area: 16)
        case .chainArc:
            p = WeaponParams(damage: 9 + 4 * lv, cooldown: 1.5 - 0.1 * lv,
                             count: 2 + level, speed: 0, pierce: 0, area: 150)
        case .seekerSwarm:
            p = WeaponParams(damage: 8 + 3 * lv, cooldown: 1.7 - 0.12 * lv,
                             count: 1 + level / 2, speed: 300, pierce: 0, area: 0)
        case .mineField:
            p = WeaponParams(damage: 18 + 8 * lv, cooldown: 1.9 - 0.13 * lv,
                             count: 1 + level / 3, speed: 0, pierce: 0, area: 68 + 6 * lv)
        case .prismBeam:
            p = WeaponParams(damage: 26 + 9 * lv, cooldown: 0, count: 1 + (level >= 4 ? 1 : 0),
                             speed: 1.1 + 0.12 * lv, pierce: 999, area: 13)  // dps; speed = rad/s
        }
        p.damage *= loadout.damageMultiplier
        if p.cooldown > 0 { p.cooldown *= loadout.cooldownMultiplier }
        if kind != .orbitBlades && kind != .prismBeam {
            p.count += loadout.bonusProjectiles
        }
        return p
    }
}
