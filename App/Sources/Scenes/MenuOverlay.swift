import SpriteKit
import NeonHordeCore

/// Main-menu overlay drawn above the live attract-mode run (GOAL Phase 8).
final class MenuOverlay {
    private let root = SKNode()
    private(set) var isVisible = false

    init(parent: SKNode, viewSize: CGSize) {
        root.zPosition = ZBand.hud + 40
        root.isHidden = true   // shown only when attract mode engages

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.45),
                               size: CGSize(width: viewSize.width * 2, height: viewSize.height * 2))
        root.addChild(dim)

        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "NEON"
        title.fontSize = 64
        title.fontColor = Palette.player
        title.position = CGPoint(x: 0, y: 150)
        root.addChild(title)

        let title2 = SKLabelNode(fontNamed: "Menlo-Bold")
        title2.text = "HORDE"
        title2.fontSize = 64
        title2.fontColor = Palette.enemyLow
        title2.position = CGPoint(x: 0, y: 84)
        root.addChild(title2)

        let tagline = SKLabelNode(fontNamed: "Menlo")
        tagline.text = "one thumb. ten minutes. become the storm."
        tagline.fontSize = 12
        tagline.fontColor = Palette.ui.withAlphaComponent(0.6)
        tagline.position = CGPoint(x: 0, y: 44)
        root.addChild(tagline)

        let play = SKLabelNode(fontNamed: "Menlo-Bold")
        play.text = "▶ TAP TO PLAY"
        play.fontSize = 24
        play.fontColor = Palette.ui
        play.verticalAlignmentMode = .center
        play.position = CGPoint(x: 0, y: -60)
        play.name = "menu-play"
        play.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.4, duration: 0.7),
            .fadeAlpha(to: 1.0, duration: 0.7),
        ])))
        root.addChild(play)

        let lab = SKLabelNode(fontNamed: "Menlo-Bold")
        lab.text = "◈ UPGRADE LAB"
        lab.fontSize = 17
        lab.fontColor = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        lab.verticalAlignmentMode = .center
        lab.position = CGPoint(x: 0, y: -130)
        lab.name = "menu-lab"
        root.addChild(lab)

        let stats = SKLabelNode(fontNamed: "Menlo")
        stats.name = "menu-stats"
        stats.fontSize = 12
        stats.fontColor = Palette.ui.withAlphaComponent(0.55)
        stats.position = CGPoint(x: 0, y: -viewSize.height / 2 + 46)
        root.addChild(stats)

        parent.addChild(root)
    }

    func show(meta: MetaState) {
        let mins = Int(meta.bestSurvivalSeconds) / 60
        let secs = Int(meta.bestSurvivalSeconds) % 60
        (root.childNode(withName: "menu-stats") as? SKLabelNode)?.text =
            meta.totalRuns == 0
            ? "the horde is waiting"
            : String(format: "BEST %d:%02d   ✕ %d   WINS %d   ◈ %d",
                     mins, secs, meta.bestKills, meta.victories, meta.shards)
        root.isHidden = false
        isVisible = true
    }

    func hide() {
        root.isHidden = true
        isVisible = false
    }

    /// Returns the tapped control name, if any.
    func control(at nodes: [SKNode]) -> String? {
        nodes.first { $0.name?.hasPrefix("menu-") == true }?.name
    }
}
