import SpriteKit
import NeonHordeCore

/// zPosition bands — one band per entity type so same-texture sprites batch
/// (GOAL §4). Within the enemy band each kind gets its own sub-z so SpriteKit
/// groups them by texture deterministically.
enum ZBand {
    static let backgroundFar: CGFloat = -30
    static let backgroundNear: CGFloat = -20
    static let grid: CGFloat = -10
    static let gems: CGFloat = 10
    static let enemies: CGFloat = 20      // +0.1 per kind
    static let projectiles: CGFloat = 30
    static let player: CGFloat = 40
    static let effects: CGFloat = 50
    static let hud: CGFloat = 100
}

/// Fixed-capacity pool of SKSpriteNodes sharing one texture.
/// Per frame: `beginFrame()`, then `place(...)` per entity, then `endFrame()`
/// hides the unused tail. No allocation after init.
final class SpriteNodePool {
    private let nodes: [SKSpriteNode]
    private var cursor = 0

    /// Number of nodes placed this frame (read by QA overlays/soak logging).
    var activeCount: Int { cursor }

    init(texture: SKTexture, capacity: Int, zPosition: CGFloat,
         blendMode: SKBlendMode = .add, parent: SKNode) {
        var built: [SKSpriteNode] = []
        built.reserveCapacity(capacity)
        for _ in 0..<capacity {
            let n = SKSpriteNode(texture: texture)
            n.blendMode = blendMode
            n.zPosition = zPosition
            n.isHidden = true
            parent.addChild(n)
            built.append(n)
        }
        nodes = built
    }

    func beginFrame() {
        cursor = 0
    }

    /// Places the next pooled node. Returns nil when capacity is exhausted
    /// (upstream pool caps should make that impossible). `texture` overrides
    /// the pool default (globally-synced sprite animation frames — same frame
    /// for every entity of a kind keeps SpriteKit batching intact).
    @discardableResult
    func place(x: CGFloat, y: CGFloat, rotation: CGFloat = 0, scale: CGFloat = 1,
               alpha: CGFloat = 1, texture: SKTexture? = nil,
               size: CGSize? = nil) -> SKSpriteNode? {
        guard cursor < nodes.count else { return nil }
        let n = nodes[cursor]
        cursor += 1
        n.isHidden = false
        n.position = CGPoint(x: x, y: y)
        n.zRotation = rotation
        n.setScale(scale)
        n.alpha = alpha
        if let texture { n.texture = texture }
        if let size { n.size = size }
        return n
    }

    func endFrame() {
        guard cursor < nodes.count else { return }
        for i in cursor..<nodes.count {
            if nodes[i].isHidden { break }  // tail beyond here is already hidden
            nodes[i].isHidden = true
        }
    }
}
