import SpriteKit
import NeonHordeCore

/// Level-up draft: 3 full-width cards, tap to pick (GOAL §4).
/// Built on demand — never in the per-frame hot path.
final class DraftOverlay {
    private let root = SKNode()
    private let viewSize: CGSize
    private(set) var isVisible = false

    init(parent: SKNode, viewSize: CGSize) {
        self.viewSize = viewSize
        root.zPosition = ZBand.hud + 20
        root.isHidden = true
        parent.addChild(root)
    }

    func show(draft: Draft, world: World, baker: TextureBaker) {
        root.removeAllChildren()

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.66),
                               size: CGSize(width: viewSize.width * 2, height: viewSize.height * 2))
        root.addChild(dim)

        let header = SKLabelNode(fontNamed: "Menlo-Bold")
        header.text = draft.rare ? "RARE CACHE" : "LEVEL UP — PICK ONE"
        header.fontSize = 20
        header.fontColor = draft.rare ? Palette.gem : Palette.player
        header.position = CGPoint(x: 0, y: 196)
        root.addChild(header)

        for (i, choice) in draft.choices.enumerated() {
            let card = SKSpriteNode(texture: baker.cardBG)
            card.name = "card\(i)"
            card.position = CGPoint(x: 0, y: 110 - CGFloat(i) * 122)
            if draft.rare {
                card.color = Palette.gem
                card.colorBlendFactor = 0.25
            }
            root.addChild(card)

            let title = SKLabelNode(fontNamed: "Menlo-Bold")
            title.text = cardTitle(choice, world: world, rare: draft.rare)
            title.fontSize = 19
            title.fontColor = isNew(choice, world: world) ? Palette.gem : Palette.ui
            title.horizontalAlignmentMode = .left
            title.verticalAlignmentMode = .center
            title.position = CGPoint(x: -150, y: 18)
            title.name = "card\(i)"
            card.addChild(title)

            let blurb = SKLabelNode(fontNamed: "Menlo")
            blurb.text = UpgradeCopy.blurb(for: choice)
            blurb.fontSize = 13
            blurb.fontColor = Palette.ui.withAlphaComponent(0.75)
            blurb.horizontalAlignmentMode = .left
            blurb.verticalAlignmentMode = .center
            blurb.position = CGPoint(x: -150, y: -16)
            blurb.name = "card\(i)"
            card.addChild(blurb)
        }

        root.isHidden = false
        isVisible = true
    }

    func hide() {
        root.isHidden = true
        isVisible = false
    }

    /// Returns the tapped card index, if any.
    func cardIndex(at sceneNodes: [SKNode]) -> Int? {
        for node in sceneNodes {
            if let name = node.name, name.hasPrefix("card"),
               let idx = Int(name.dropFirst(4)) {
                return idx
            }
        }
        return nil
    }

    private func isNew(_ c: UpgradeChoice, world: World) -> Bool {
        switch c {
        case .weapon(let w): return world.loadout.level(of: w) == 0
        case .passive(let p): return world.loadout.level(of: p) == 0
        }
    }

    private func cardTitle(_ c: UpgradeChoice, world: World, rare: Bool) -> String {
        let step = rare ? 2 : 1
        switch c {
        case .weapon(let w):
            let lv = world.loadout.level(of: w)
            return lv == 0 ? "\(c.title)  [NEW]"
                           : "\(c.title)  LV \(lv)→\(min(Loadout.maxLevel, lv + step))"
        case .passive(let p):
            let lv = world.loadout.level(of: p)
            return lv == 0 ? "\(c.title)  [NEW]" : "\(c.title)  LV \(lv)→\(lv + 1)"
        }
    }
}

/// One-line effect copy per upgrade (UI-only strings live app-side).
enum UpgradeCopy {
    static func blurb(for c: UpgradeChoice) -> String {
        switch c {
        case .weapon(.pulseBolt): return "Auto-fires at the nearest enemy"
        case .weapon(.orbitBlades): return "Blades circle you, grinding the swarm"
        case .weapon(.novaBurst): return "Periodic shockwave around you"
        case .weapon(.railLance): return "Pierces the densest enemy line"
        case .weapon(.chainArc): return "Lightning that jumps between enemies"
        case .weapon(.seekerSwarm): return "Homing missiles hunt stragglers"
        case .weapon(.mineField): return "Proximity mines carpet your trail"
        case .weapon(.prismBeam): return "Rotating laser sweep"
        case .passive(.damage): return "+12% damage per level"
        case .passive(.cooldown): return "Weapons fire faster"
        case .passive(.moveSpeed): return "+7% move speed per level"
        case .passive(.magnet): return "Gems fly to you from farther away"
        case .passive(.maxHP): return "+20 max HP, heals on pick"
        case .passive(.armor): return "Flat damage reduction per hit"
        case .passive(.projectileCount): return "+1 projectile at LV 1/3/5"
        case .passive(.xpGain): return "+10% XP per level"
        }
    }
}
