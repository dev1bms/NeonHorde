import SpriteKit

/// Infinite scrolling background: a 3×3 sheet of tiles per layer, repositioned
/// modulo tile size against the camera (grid + two parallax starfields).
final class BackgroundRig {
    private struct Layer {
        let node: SKNode
        let tileSize: CGFloat
        let parallax: CGFloat   // 1 = moves with world, <1 = drifts slower (far away)
    }

    private var layers: [Layer] = []

    init(parent: SKNode, baker: TextureBaker, viewSize: CGSize) {
        // Enough tiles to cover the largest phone + one tile margin.
        func makeLayer(texture: SKTexture, tileSize: CGFloat, parallax: CGFloat,
                       z: CGFloat, alpha: CGFloat) {
            let holder = SKNode()
            holder.zPosition = z
            let cols = Int(ceil(viewSize.width / tileSize)) + 2
            let rows = Int(ceil(viewSize.height / tileSize)) + 2
            for cx in 0..<cols {
                for cy in 0..<rows {
                    let t = SKSpriteNode(texture: texture)
                    t.anchorPoint = .zero
                    t.blendMode = .add
                    t.alpha = alpha
                    t.position = CGPoint(x: CGFloat(cx) * tileSize, y: CGFloat(cy) * tileSize)
                    holder.addChild(t)
                }
            }
            parent.addChild(holder)
            layers.append(Layer(node: holder, tileSize: tileSize, parallax: parallax))
        }

        makeLayer(texture: baker.starfieldFar, tileSize: 512, parallax: 0.15,
                  z: ZBand.backgroundFar, alpha: 0.8)
        makeLayer(texture: baker.starfieldNear, tileSize: 512, parallax: 0.4,
                  z: ZBand.backgroundNear, alpha: 0.9)
        makeLayer(texture: baker.gridTile, tileSize: 256, parallax: 1.0,
                  z: ZBand.grid, alpha: 1.0)
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
