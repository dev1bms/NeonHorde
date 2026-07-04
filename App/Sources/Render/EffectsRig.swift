import SpriteKit
import NeonHordeCore

/// Transient visual effects (nova rings, beam flashes, chain arcs, blasts).
/// Pre-allocated node pool with manual lifetimes — no SKActions, no churn.
final class EffectsRig {
    private struct Effect {
        var node: SKSpriteNode
        var age: CGFloat = 0
        var ttl: CGFloat = 0
        var kind: Kind = .ringExpand
        var startScale: CGFloat = 1
        var endScale: CGFloat = 1
    }

    enum Kind {
        case ringExpand    // scale up, fade out
        case beamFade      // hold shape, fade out
    }

    private var effects: [Effect] = []
    private var free: [SKSpriteNode] = []
    private let capacity = 48

    init(parent: SKNode) {
        for _ in 0..<capacity {
            let n = SKSpriteNode()
            n.blendMode = .add
            n.zPosition = ZBand.effects
            n.isHidden = true
            parent.addChild(n)
            free.append(n)
        }
        effects.reserveCapacity(capacity)
    }

    // MARK: Spawners (drop silently when the pool is dry — they're cosmetic)

    func ring(at pos: CGPoint, texture: SKTexture, fromRadius: CGFloat, toRadius: CGFloat,
              ttl: CGFloat = 0.35, color: UIColor? = nil) {
        guard let node = free.popLast() else { return }
        node.texture = texture
        node.size = texture.size()
        node.position = pos
        node.zRotation = 0
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.color = color ?? .white
        node.colorBlendFactor = color == nil ? 0 : 1
        node.isHidden = false
        node.alpha = 0.9
        let base = texture.size().width / 2   // ring texture radius 60
        var e = Effect(node: node)
        e.kind = .ringExpand
        e.ttl = ttl
        e.startScale = fromRadius / base
        e.endScale = toRadius / base
        node.setScale(e.startScale)
        effects.append(e)
    }

    /// Straight glow bar from `start` toward `angle` with `length` points.
    func beam(from start: CGPoint, angle: CGFloat, length: CGFloat,
              thickness: CGFloat, texture: SKTexture, ttl: CGFloat = 0.22) {
        guard let node = free.popLast() else { return }
        node.texture = texture
        node.anchorPoint = CGPoint(x: 0, y: 0.5)
        node.position = start
        node.zRotation = angle
        node.size = CGSize(width: length, height: thickness)
        node.isHidden = false
        node.alpha = 1
        node.color = .white
        node.colorBlendFactor = 0
        var e = Effect(node: node)
        e.kind = .beamFade
        e.ttl = ttl
        e.startScale = 1
        e.endScale = 1
        node.xScale = 1
        node.yScale = 1
        effects.append(e)
    }

    /// Polyline lightning: one beam segment per pair of points.
    func chain(points: [CGPoint], texture: SKTexture) {
        guard points.count >= 2 else { return }
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let dx = b.x - a.x, dy = b.y - a.y
            beam(from: a, angle: atan2(dy, dx), length: sqrt(dx * dx + dy * dy),
                 thickness: 7, texture: texture, ttl: 0.18)
        }
    }

    func update(dt: CGFloat) {
        var i = 0
        while i < effects.count {
            effects[i].age += dt
            let e = effects[i]
            let t = min(1, e.age / max(e.ttl, 0.001))
            switch e.kind {
            case .ringExpand:
                let s = e.startScale + (e.endScale - e.startScale) * t
                e.node.setScale(s)
                e.node.alpha = 0.9 * (1 - t)
            case .beamFade:
                e.node.alpha = 1 - t * t
            }
            if e.age >= e.ttl {
                e.node.isHidden = true
                free.append(e.node)
                effects.swapAt(i, effects.count - 1)
                effects.removeLast()
            } else {
                i += 1
            }
        }
    }
}
