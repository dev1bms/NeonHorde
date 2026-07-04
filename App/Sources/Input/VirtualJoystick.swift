import SpriteKit
import NeonHordeCore

/// Floating one-thumb joystick (GOAL §4): touch anywhere sets the origin,
/// drag steers; magnitude clamps at `radius` points. Purely visual nodes are
/// parented to the HUD layer (camera space).
final class VirtualJoystick {
    private let radius: CGFloat = 52
    private let base: SKSpriteNode
    private let knob: SKSpriteNode
    private var origin: CGPoint?
    private var touch: UITouch?

    /// Current input vector, magnitude 0...1.
    private(set) var vector = Vec2.zero

    init(parent: SKNode, baker: TextureBaker) {
        base = SKSpriteNode(texture: baker.joystickBase)
        knob = SKSpriteNode(texture: baker.joystickKnob)
        for n in [base, knob] {
            n.zPosition = ZBand.hud
            n.alpha = 0
            n.blendMode = .add
            parent.addChild(n)
        }
    }

    func touchBegan(_ t: UITouch, location: CGPoint) {
        guard touch == nil else { return }
        touch = t
        origin = location
        base.position = location
        knob.position = location
        base.alpha = 0.9
        knob.alpha = 0.9
        vector = .zero
    }

    func touchMoved(_ t: UITouch, location: CGPoint) {
        guard t === touch, let origin else { return }
        var dx = location.x - origin.x
        var dy = location.y - origin.y
        let len = sqrt(dx * dx + dy * dy)
        if len > radius {
            dx *= radius / len
            dy *= radius / len
        }
        knob.position = CGPoint(x: origin.x + dx, y: origin.y + dy)
        vector = Vec2(Float(dx / radius), Float(dy / radius))
    }

    func touchEnded(_ t: UITouch) {
        guard t === touch else { return }
        touch = nil
        origin = nil
        vector = .zero
        base.alpha = 0
        knob.alpha = 0
    }
}
