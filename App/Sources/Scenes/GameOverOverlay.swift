import SpriteKit
import NeonHordeCore

/// Camera-space run-over overlay. Restart is a tap anywhere (< 1 s, GOAL §4).
final class GameOverOverlay {
    private let root = SKNode()

    var isVisible: Bool { !root.isHidden }

    init(parent: SKNode, viewSize: CGSize) {
        root.zPosition = ZBand.hud + 10
        root.isHidden = true

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.72),
                               size: CGSize(width: viewSize.width * 2, height: viewSize.height * 2))
        root.addChild(dim)

        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "RUN OVER"
        title.fontSize = 40
        title.fontColor = Palette.enemyLow
        title.position = CGPoint(x: 0, y: 80)
        root.addChild(title)

        let stats = SKLabelNode(fontNamed: "Menlo")
        stats.name = "stats"
        stats.fontSize = 17
        stats.fontColor = Palette.ui
        stats.position = CGPoint(x: 0, y: 30)
        root.addChild(stats)

        let shards = SKLabelNode(fontNamed: "Menlo-Bold")
        shards.name = "shards"
        shards.fontSize = 18
        shards.fontColor = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        shards.position = CGPoint(x: 0, y: -8)
        root.addChild(shards)

        let retry = SKLabelNode(fontNamed: "Menlo-Bold")
        retry.text = "TAP TO RETRY"
        retry.fontSize = 20
        retry.fontColor = Palette.player
        retry.position = CGPoint(x: 0, y: -60)
        retry.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.35, duration: 0.55),
            .fadeAlpha(to: 1.0, duration: 0.55),
        ])))
        root.addChild(retry)

        let lab = SKLabelNode(fontNamed: "Menlo-Bold")
        lab.text = "◈ UPGRADE LAB"
        lab.name = "labButton"
        lab.fontSize = 17
        lab.fontColor = UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        lab.position = CGPoint(x: 0, y: -110)
        root.addChild(lab)

        parent.addChild(root)
    }

    func setShardsEarned(_ n: Int) {
        (root.childNode(withName: "shards") as? SKLabelNode)?.text = "◈ +\(n)"
    }

    func show(world: World) {
        setTitle("RUN OVER", color: Palette.enemyLow)
        let t = Int(world.time)
        (root.childNode(withName: "stats") as? SKLabelNode)?.text =
            String(format: "%d:%02d survived   ✕ %d   LV %d", t / 60, t % 60, world.kills, world.player.level)
        root.isHidden = false
    }

    func showVictory(world: World) {
        setTitle("HORDE BROKEN", color: Palette.gem)
        let t = Int(world.time)
        (root.childNode(withName: "stats") as? SKLabelNode)?.text =
            String(format: "PRIME fell at %d:%02d   ✕ %d   LV %d", t / 60, t % 60, world.kills, world.player.level)
        root.isHidden = false
    }

    private func setTitle(_ text: String, color: UIColor) {
        for child in root.children {
            if let label = child as? SKLabelNode, label.fontSize == 40 {
                label.text = text
                label.fontColor = color
            }
        }
    }

    func hide() {
        root.isHidden = true
    }
}
