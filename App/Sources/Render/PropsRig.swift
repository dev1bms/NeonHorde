import SpriteKit
import NeonHordeCore

/// Deterministic forest-prop scattering with zero storage: each 512-pt world
/// cell hashes to (has prop?, which, offset). A small node pool dresses the
/// cells currently in view. No-op until props art exists.
final class PropsRig {
    private var nodes: [SKSpriteNode] = []
    private let props: [SKTexture]
    private let cell: CGFloat = 512

    init(parent: SKNode, art: ArtLibrary) {
        props = art.props
        guard !props.isEmpty else { return }
        for _ in 0..<24 {
            let n = SKSpriteNode(texture: props[0])
            n.zPosition = ZBand.grid + 1     // above ground, below gems
            n.isHidden = true
            n.alpha = 0.9
            parent.addChild(n)
            nodes.append(n)
        }
    }

    func update(cameraPosition c: CGPoint, viewSize: CGSize) {
        guard !props.isEmpty else { return }
        var used = 0
        let minCX = Int(floor((c.x - viewSize.width / 2 - cell) / cell))
        let maxCX = Int(ceil((c.x + viewSize.width / 2 + cell) / cell))
        let minCY = Int(floor((c.y - viewSize.height / 2 - cell) / cell))
        let maxCY = Int(ceil((c.y + viewSize.height / 2 + cell) / cell))
        for cx in minCX...maxCX {
            for cy in minCY...maxCY {
                guard used < nodes.count else { break }
                let h = hash(cx, cy)
                guard h % 100 < 38 else { continue }   // 38% of cells hold a prop
                let n = nodes[used]
                used += 1
                let texIndex = Int(h >> 8) % props.count
                n.texture = props[texIndex]
                let size = 60 + CGFloat((h >> 16) % 50)
                n.size = CGSize(width: size, height: size)
                let ox = CGFloat((h >> 24) % 400) - 200
                let oy = CGFloat((h >> 32) % 400) - 200
                n.position = CGPoint(x: CGFloat(cx) * cell + cell / 2 + ox,
                                     y: CGFloat(cy) * cell + cell / 2 + oy)
                n.isHidden = false
            }
        }
        for i in used..<nodes.count { nodes[i].isHidden = true }
    }

    private func hash(_ x: Int, _ y: Int) -> UInt64 {
        var h = UInt64(bitPattern: Int64(x)) &* 92_837_111
        h ^= UInt64(bitPattern: Int64(y)) &* 689_287_499
        h = (h ^ (h >> 13)) &* 0x9E37_79B9_7F4A_7C15
        return h ^ (h >> 31)
    }
}
