import SpriteKit
import NeonHordeCore

/// Bakes every runtime sprite texture ONCE at launch (GOAL §4 rendering rules).
/// SKShapeNode is used only here, never at runtime. Glow = stacked concentric
/// fill layers (never SKShapeNode.glowWidth — inconsistent falloff).
final class TextureBaker {
    private unowned let view: SKView

    private(set) var player: SKTexture!
    private(set) var enemyTextures: [EnemyKind: SKTexture] = [:]
    private(set) var projectile: SKTexture!
    private(set) var gem: SKTexture!
    private(set) var blade: SKTexture!          // orbit blades
    private(set) var mine: SKTexture!
    private(set) var ring: SKTexture!           // nova / mine blast (scaled)
    private(set) var beamSegment: SKTexture!    // stretched for lances/beams/arcs
    private(set) var cardBG: SKTexture!         // draft card background
    private(set) var bossTexture: SKTexture!
    private(set) var enemyShot: SKTexture!
    private(set) var chest: SKTexture!
    private(set) var joystickBase: SKTexture!
    private(set) var joystickKnob: SKTexture!
    private(set) var gridTile: SKTexture!
    private(set) var starfieldNear: SKTexture!
    private(set) var starfieldFar: SKTexture!
    private(set) var digits: [SKTexture] = []      // 0-9 glyphs for damage numbers

    init(view: SKView) {
        self.view = view
        bakeAll()
    }

    private func bakeAll() {
        player = bakeGlow(shape: .circle, radius: CGFloat(Balance.playerRadius), color: Palette.player)
        for kind in EnemyKind.allCases {
            let stats = Balance.stats(for: kind)
            let color = Palette.enemy(threat: CGFloat(stats.threat))
            enemyTextures[kind] = bakeGlow(shape: shape(for: kind),
                                           radius: CGFloat(stats.radius),
                                           color: color)
        }
        projectile = bakeGlow(shape: .circle, radius: CGFloat(Balance.boltRadius),
                              color: Palette.player, glowScale: 1.6)
        gem = bakeGlow(shape: .diamond, radius: 7, color: Palette.gem, glowScale: 1.3)
        blade = bakeGlow(shape: .triangle, radius: 11, color: Palette.player, glowScale: 1.4)
        mine = bakeGlow(shape: .hexagon, radius: 9, color: Palette.enemyHigh, glowScale: 1.5)
        ring = bakeRing(radius: 60, lineAlpha: 0.9, lineWidth: 5, color: Palette.player)
        beamSegment = bakeBeamSegment()
        cardBG = bakeCardBG()
        bossTexture = bakeBoss()
        enemyShot = bakeGlow(shape: .circle, radius: CGFloat(Balance.enemyShotRadius),
                             color: Palette.enemyHigh, glowScale: 1.7)
        chest = bakeGlow(shape: .diamond, radius: 15, color: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1),
                         glowScale: 1.6)
        joystickBase = bakeRing(radius: 52, lineAlpha: 0.25)
        joystickKnob = bakeGlow(shape: .circle, radius: 18, color: Palette.ui.withAlphaComponent(0.6), glowScale: 1.3)
        gridTile = bakeGridTile(size: 256, spacing: 64)
        starfieldNear = bakeStarfield(size: 512, stars: 26, seed: 11, maxR: 1.8)
        starfieldFar = bakeStarfield(size: 512, stars: 40, seed: 22, maxR: 1.1)
        digits = (0...9).map { bakeDigit($0) }
    }

    // MARK: - Shapes

    enum Shape {
        case circle, triangle, square, pentagon, diamond, hexagon
    }

    private func shape(for kind: EnemyKind) -> Shape {
        switch kind {
        case .dart: return .triangle
        case .brick: return .square
        case .splitter: return .pentagon
        case .weaver: return .diamond
        case .spitter: return .hexagon
        }
    }

    private func path(_ shape: Shape, radius r: CGFloat) -> CGPath {
        switch shape {
        case .circle:
            return CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        case .square:
            return CGPath(rect: CGRect(x: -r * 0.85, y: -r * 0.85, width: 1.7 * r, height: 1.7 * r), transform: nil)
        case .diamond:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: r))
            p.addLine(to: CGPoint(x: r * 0.62, y: 0))
            p.addLine(to: CGPoint(x: 0, y: -r))
            p.addLine(to: CGPoint(x: -r * 0.62, y: 0))
            p.closeSubpath()
            return p
        case .triangle:
            return polygon(sides: 3, radius: r)
        case .pentagon:
            return polygon(sides: 5, radius: r)
        case .hexagon:
            return polygon(sides: 6, radius: r)
        }
    }

    private func polygon(sides: Int, radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<sides {
            let a = CGFloat(i) / CGFloat(sides) * 2 * .pi + .pi / 2
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    // MARK: - Bakes

    private func bake(_ node: SKNode) -> SKTexture {
        guard let tex = view.texture(from: node) else {
            fatalError("texture(from:) returned nil — baking must run on the main thread with a live SKView")
        }
        return tex
    }

    /// Core shape + two enlarged translucent copies = cheap, consistent glow.
    private func bakeGlow(shape: Shape, radius: CGFloat, color: UIColor, glowScale: CGFloat = 1.0) -> SKTexture {
        let root = SKNode()
        let layers: [(scale: CGFloat, alpha: CGFloat)] = [
            (1.9 * glowScale, 0.10), (1.45 * glowScale, 0.22), (1.0, 1.0),
        ]
        for l in layers {
            let s = SKShapeNode(path: path(shape, radius: radius * l.scale))
            s.fillColor = color.withAlphaComponent(l.alpha)
            s.strokeColor = .clear
            root.addChild(s)
        }
        return bake(root)
    }

    private func bakeRing(radius: CGFloat, lineAlpha: CGFloat,
                          lineWidth: CGFloat = 2, color: UIColor? = nil) -> SKTexture {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.strokeColor = (color ?? Palette.ui).withAlphaComponent(lineAlpha)
        ring.lineWidth = lineWidth
        ring.fillColor = .clear
        return bake(ring)
    }

    /// 64×10 horizontal glow bar — stretch xScale for beams/arcs.
    private func bakeBeamSegment() -> SKTexture {
        let root = SKNode()
        let core = SKShapeNode(rect: CGRect(x: 0, y: -2, width: 64, height: 4))
        core.fillColor = Palette.ui
        core.strokeColor = .clear
        let glow = SKShapeNode(rect: CGRect(x: 0, y: -5, width: 64, height: 10))
        glow.fillColor = Palette.player.withAlphaComponent(0.35)
        glow.strokeColor = .clear
        root.addChild(glow)
        root.addChild(core)
        return bake(root)
    }

    /// PRIME: nested rotating nonagons, magenta core with orange halo.
    private func bakeBoss() -> SKTexture {
        let root = SKNode()
        let r = CGFloat(Balance.bossRadius)
        let layers: [(scale: CGFloat, alpha: CGFloat, color: UIColor)] = [
            (2.0, 0.10, Palette.enemyHigh),
            (1.5, 0.20, Palette.enemyHigh),
            (1.0, 1.00, Palette.enemyLow),
            (0.62, 0.9, Palette.uiBackground),
            (0.38, 1.0, Palette.enemyHigh),
        ]
        for (i, l) in layers.enumerated() {
            let shape = SKShapeNode(path: polygon(sides: 9, radius: r * l.scale))
            shape.fillColor = l.color.withAlphaComponent(l.alpha)
            shape.strokeColor = .clear
            shape.zRotation = CGFloat(i) * 0.2
            root.addChild(shape)
        }
        return bake(root)
    }

    private func bakeCardBG() -> SKTexture {
        let rect = CGRect(x: -170, y: -52, width: 340, height: 104)
        let card = SKShapeNode(rect: rect, cornerRadius: 14)
        card.fillColor = UIColor(white: 0.09, alpha: 0.96)
        card.strokeColor = Palette.player.withAlphaComponent(0.55)
        card.lineWidth = 1.5
        return bake(card)
    }

    private func bakeGridTile(size: CGFloat, spacing: CGFloat) -> SKTexture {
        let root = SKNode()
        let color = Palette.player.withAlphaComponent(0.06)
        var offset: CGFloat = 0
        while offset <= size {
            let v = SKShapeNode(rect: CGRect(x: offset - 0.5, y: 0, width: 1, height: size))
            v.fillColor = color
            v.strokeColor = .clear
            let h = SKShapeNode(rect: CGRect(x: 0, y: offset - 0.5, width: size, height: 1))
            h.fillColor = color
            h.strokeColor = .clear
            root.addChild(v)
            root.addChild(h)
            offset += spacing
        }
        // Anchor the tile bounds so the texture is exactly size×size.
        let frame = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size, height: size))
        frame.fillColor = .clear
        frame.strokeColor = .clear
        root.addChild(frame)
        return bake(root)
    }

    private func bakeStarfield(size: CGFloat, stars: Int, seed: UInt64, maxR: CGFloat) -> SKTexture {
        let root = SKNode()
        var rng = SplitMix64(seed: seed)
        for _ in 0..<stars {
            let x = CGFloat(rng.unitFloat()) * size
            let y = CGFloat(rng.unitFloat()) * size
            let r = CGFloat(rng.float(in: 0.4...Float(maxR)))
            let alpha = CGFloat(rng.float(in: 0.15...0.6))
            let star = SKShapeNode(circleOfRadius: r)
            star.fillColor = Palette.ui.withAlphaComponent(alpha)
            star.strokeColor = .clear
            star.position = CGPoint(x: x, y: y)
            root.addChild(star)
        }
        let frame = SKShapeNode(rect: CGRect(x: 0, y: 0, width: size, height: size))
        frame.fillColor = .clear
        frame.strokeColor = .clear
        root.addChild(frame)
        return bake(root)
    }

    private func bakeDigit(_ d: Int) -> SKTexture {
        let label = SKLabelNode(text: "\(d)")
        label.fontName = "Menlo-Bold"
        label.fontSize = 18
        label.fontColor = Palette.ui
        label.verticalAlignmentMode = .center
        return bake(label)
    }
}
