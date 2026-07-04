import SpriteKit

/// Infinite scrolling background: a 3×3 sheet of tiles per layer, repositioned
/// modulo tile size against the camera. With forest art (AMENDMENT v3) the
/// ground layer swaps textures per stage; otherwise the neon grid tints.
final class BackgroundRig {
    private struct Layer {
        let node: SKNode
        let tileSize: CGFloat
        let parallax: CGFloat   // 1 = moves with world, <1 = drifts slower (far away)
    }

    private var layers: [Layer] = []
    private var groundTiles: [SKSpriteNode] = []
    private let stageGrounds: [SKTexture]
    private let stageGridTints: [UIColor] = [
        Palette.player,
        UIColor(red: 0.72, green: 0.4, blue: 1.0, alpha: 1),
        UIColor(red: 1.0, green: 0.35, blue: 0.25, alpha: 1),
    ]
    private var currentStage = -1

    init(parent: SKNode, baker: TextureBaker, art: ArtLibrary, viewSize: CGSize) {
        stageGrounds = art.grounds
        // Enough tiles to cover the largest phone + one tile margin.
        func makeLayer(texture: SKTexture, tileSize: CGFloat, parallax: CGFloat,
                       z: CGFloat, alpha: CGFloat, blend: SKBlendMode = .add,
                       collect: Bool = false) {
            let holder = SKNode()
            holder.zPosition = z
            let cols = Int(ceil(viewSize.width / tileSize)) + 2
            let rows = Int(ceil(viewSize.height / tileSize)) + 2
            for cx in 0..<cols {
                for cy in 0..<rows {
                    let t = SKSpriteNode(texture: texture)
                    t.anchorPoint = .zero
                    t.blendMode = blend
                    t.alpha = alpha
                    t.size = CGSize(width: tileSize, height: tileSize)
                    t.position = CGPoint(x: CGFloat(cx) * tileSize, y: CGFloat(cy) * tileSize)
                    holder.addChild(t)
                    if collect { groundTiles.append(t) }
                }
            }
            parent.addChild(holder)
            layers.append(Layer(node: holder, tileSize: tileSize, parallax: parallax))
        }

        if let forest = stageGrounds.first {
            // Forest mode: opaque painted ground, subtle drifting mist above it.
            makeLayer(texture: forest, tileSize: 512, parallax: 1.0,
                      z: ZBand.grid, alpha: 1.0, blend: .alpha, collect: true)
            makeLayer(texture: baker.starfieldFar, tileSize: 512, parallax: 0.3,
                      z: ZBand.grid + 0.5, alpha: 0.25)   // stars double as fireflies
        } else {
            makeLayer(texture: baker.starfieldFar, tileSize: 512, parallax: 0.15,
                      z: ZBand.backgroundFar, alpha: 0.8)
            makeLayer(texture: baker.starfieldNear, tileSize: 512, parallax: 0.4,
                      z: ZBand.backgroundNear, alpha: 0.9)
            makeLayer(texture: baker.gridTile, tileSize: 256, parallax: 1.0,
                      z: ZBand.grid, alpha: 1.0, collect: true)
        }
    }

    /// Swap ground art (or tint the neon grid) when a stage gate is crossed.
    func setStage(_ stage: Int) {
        guard stage != currentStage else { return }
        currentStage = stage
        if stageGrounds.count > stage, !stageGrounds.isEmpty {
            for tile in groundTiles { tile.texture = stageGrounds[stage] }
        } else if stageGrounds.isEmpty {
            let tint = stageGridTints[min(stage, stageGridTints.count - 1)]
            for tile in groundTiles {
                tile.color = tint
                tile.colorBlendFactor = stage == 0 ? 0 : 0.7
            }
        }
    }

    /// Call once per frame with the camera's world position.
    func update(cameraPosition c: CGPoint, viewSize: CGSize) {
        for layer in layers {
            let effective = CGPoint(x: c.x * layer.parallax, y: c.y * layer.parallax)
            let ox = effective.x.truncatingRemainder(dividingBy: layer.tileSize)
            let oy = effective.y.truncatingRemainder(dividingBy: layer.tileSize)
            layer.node.position = CGPoint(
                x: c.x - ox - viewSize.width / 2 - layer.tileSize,
                y: c.y - oy - viewSize.height / 2 - layer.tileSize
            )
        }
    }
}
