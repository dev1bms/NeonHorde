import SpriteKit
import NeonHordeCore

/// Pause overlay (GOAL §4 Session shape): freezes the sim; offers Resume,
/// the three settings toggles, and Abandon Run (banks shards earned so far).
final class PauseOverlay {
    private let root = SKNode()
    private(set) var isVisible = false

    init(parent: SKNode, viewSize: CGSize) {
        root.zPosition = ZBand.hud + 30
        root.isHidden = true

        let dim = SKSpriteNode(color: UIColor.black.withAlphaComponent(0.78),
                               size: CGSize(width: viewSize.width * 2, height: viewSize.height * 2))
        root.addChild(dim)

        let title = SKLabelNode(fontNamed: "Menlo-Bold")
        title.text = "PAUSED"
        title.fontSize = 34
        title.fontColor = Palette.player
        title.position = CGPoint(x: 0, y: 150)
        root.addChild(title)

        addButton("RESUME", name: "resume", y: 70, color: Palette.player, size: 22)
        addButton("", name: "toggle-music", y: 10, color: Palette.ui, size: 16)
        addButton("", name: "toggle-sfx", y: -30, color: Palette.ui, size: 16)
        addButton("", name: "toggle-haptics", y: -70, color: Palette.ui, size: 16)
        addButton("ABANDON RUN", name: "abandon", y: -150, color: Palette.enemyLow, size: 18)

        parent.addChild(root)
    }

    private func addButton(_ text: String, name: String, y: CGFloat,
                           color: UIColor, size: CGFloat) {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: y)
        label.name = name
        root.addChild(label)
    }

    func show(meta: MetaState) {
        refreshToggles(meta: meta)
        root.isHidden = false
        isVisible = true
    }

    func hide() {
        root.isHidden = true
        isVisible = false
    }

    func refreshToggles(meta: MetaState) {
        setToggle("toggle-music", label: "MUSIC", on: meta.musicOn)
        setToggle("toggle-sfx", label: "SFX", on: meta.sfxOn)
        setToggle("toggle-haptics", label: "HAPTICS", on: meta.hapticsOn)
    }

    private func setToggle(_ name: String, label: String, on: Bool) {
        (root.childNode(withName: name) as? SKLabelNode)?.text =
            "\(label)  \(on ? "▣ ON" : "▢ OFF")"
    }

    /// Returns the tapped control name, if any.
    func control(at nodes: [SKNode]) -> String? {
        for node in nodes {
            if let name = node.name,
               ["resume", "abandon", "toggle-music", "toggle-sfx", "toggle-haptics"].contains(name) {
                return name
            }
        }
        return nil
    }
}
