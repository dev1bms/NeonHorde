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
        // Enough tiles to cover the largest phone + wrap-period margin.
        // wrapPeriod defaults to tileSize; mirror-tiled grounds repeat every
        // TWO tiles, so they wrap at 2× and need extra coverage.
        func makeLayer(texture: SKTexture, tileSize: CGFloat, parallax: CGFloat,
                       z: CGFloat, alpha: CGFloat, blend: SKBlendMode = .add,
                       collect: Bool = false, wrapPeriod: CGFloat? = nil) {
            let period = wrapPeriod ?? tileSize
            let holder = SKNode()
            holder.zPosition = z
            let cols = Int(ceil((viewSize.width + 2 * period) / tileSize)) + 1
            let rows = Int(ceil((viewSize.height + 2 * period) / tileSize)) + 1
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
            layers.append(Layer(node: holder, tileSize: period, parallax: parallax))
        }

        if let forest = stageGrounds.first {
            // Forest mode: opaque painted ground, subtle drifting mist above it.
            makeLayer(texture: forest, tileSize: 512, parallax: 1.0,
                      z: ZBand.grid, alpha: 1.0, blend: .alpha, collect: true,
                      wrapPeriod: 1024)
            // The stage grounds are generated as SEAMLESS tileables (verified
            // offline: wrap-edge diff 4–12/255), so straight repetition looks
            // most organic. If future drops aren't seamless, set this true to
            // mirror alternate tiles (seam-free for any texture, but visibly
            // kaleidoscopic).
            let mirrorGrounds = false
            if mirrorGrounds {
                for tile in groundTiles {
                    let cx = Int(round(tile.position.x / 512))
                    let cy = Int(round(tile.position.y / 512))
                    tile.xScale = cx % 2 == 0 ? 1 : -1
                    tile.yScale = cy % 2 == 0 ? 1 : -1
                    if tile.xScale < 0 { tile.anchorPoint.x = 1 }
                    if tile.yScale < 0 { tile.anchorPoint.y = 1 }
                }
            }
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
