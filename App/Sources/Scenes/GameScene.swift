import SpriteKit

/// Phase 1 placeholder: animated glowing shape proving the render pipeline.
/// Replaced by the real game scene in Phase 2+.
final class GameScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = Palette.uiBackground

        let core = SKShapeNode(circleOfRadius: 28)
        core.fillColor = Palette.player
        core.strokeColor = .clear
        core.position = CGPoint(x: frame.midX, y: frame.midY)
        core.blendMode = .add

        let halo = SKShapeNode(circleOfRadius: 44)
        halo.fillColor = Palette.player.withAlphaComponent(0.25)
        halo.strokeColor = .clear
        halo.blendMode = .add
        core.addChild(halo)

        core.run(.repeatForever(.sequence([
            .scale(to: 1.25, duration: 0.8),
            .scale(to: 1.0, duration: 0.8),
        ])))
        addChild(core)

        let label = SKLabelNode(text: "NEON HORDE")
        label.fontName = "Menlo-Bold"
        label.fontSize = 28
        label.fontColor = Palette.ui
        label.position = CGPoint(x: frame.midX, y: frame.midY + 120)
        addChild(label)
    }
}
