/// Level-up draft generation and application (GOAL §4).
extension World {
    /// Generates 3 weighted choices. Owned items are weighted up; maxed items
    /// and slots-full categories are excluded. `rare` drafts (elite chests)
    /// grant +2 levels on weapons instead of +1.
    mutating func generateDraft(rare: Bool) {
        var candidates: [(UpgradeChoice, Float)] = []

        let weaponsFull = loadout.ownedWeaponCount >= Loadout.maxWeapons
        for kind in WeaponKind.allCases {
            let lv = loadout.level(of: kind)
            guard lv < Loadout.maxLevel else { continue }
            if lv == 0 && weaponsFull { continue }
            let weight: Float = lv > 0 ? 2.0 : 1.0
            candidates.append((.weapon(kind), weight))
        }
        let passivesFull = loadout.ownedPassiveCount >= Loadout.maxPassives
        for kind in PassiveKind.allCases {
            let lv = loadout.level(of: kind)
            guard lv < Loadout.maxLevel else { continue }
            if lv == 0 && passivesFull { continue }
            let weight: Float = lv > 0 ? 1.6 : 0.8
            candidates.append((.passive(kind), weight))
        }

        guard !candidates.isEmpty else {
            pendingDraft = nil   // everything maxed — auto-skip
            return
        }

        var picks: [UpgradeChoice] = []
        for _ in 0..<min(3, candidates.count) {
            var total: Float = 0
            for c in candidates { total += c.1 }
            var roll = rng.unitFloat() * total
            var chosen = 0
            for (i, c) in candidates.enumerated() {
                roll -= c.1
                if roll <= 0 {
                    chosen = i
                    break
                }
            }
            picks.append(candidates[chosen].0)
            candidates.remove(at: chosen)
        }
        pendingDraft = Draft(choices: picks, rare: rare)
    }

    /// UI/bot entry point: applies choice `index` and resumes the sim.
    public mutating func applyDraft(_ index: Int) {
        guard let draft = pendingDraft, draft.choices.indices.contains(index) else { return }
        let step = draft.rare ? 2 : 1
        switch draft.choices[index] {
        case .weapon(let w):
            loadout.weaponLevels[w.rawValue] =
                min(Loadout.maxLevel, loadout.weaponLevels[w.rawValue] + step)
        case .passive(let p):
            let before = loadout.bonusMaxHP
            loadout.passiveLevels[p.rawValue] =
                min(Loadout.maxLevel, loadout.passiveLevels[p.rawValue] + 1)
            if p == .maxHP {
                let gained = loadout.bonusMaxHP - before
                player.maxHP = Balance.playerMaxHP + loadout.bonusMaxHP
                player.hp += gained   // picking BULWARK also heals the delta
            }
        }
        pendingDraft = nil
        drainQueuedLevelUps()
    }

    /// Test-only: refuse the draft (baseline comparisons need an un-upgraded run).
    internal mutating func declineDraft() {
        pendingDraft = nil
        drainQueuedLevelUps()
    }

    mutating func drainQueuedLevelUps() {
        if queuedLevelUps > 0 {
            queuedLevelUps -= 1
            generateDraft(rare: false)
        }
    }
}
