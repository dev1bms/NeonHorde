import SpriteKit
import NeonHordeCore

/// The Upgrade Lab: permanent upgrades, cosmetics, Overdrive tier, stats.
/// Static UI — plain nodes, rebuilt on every purchase (not a hot path).
final class UpgradeLabScene: SKScene {
    private var meta = SaveStore.load()
    private let shapeNames = ["CIRCLE", "TRIANGLE", "STAR", "HEX"]
    private let trailNames = ["CYAN", "MAGENTA", "LIME", "GOLD"]
    private let shapePrice = 200
    private let trailPrice = 150

    override func didMove(to view: SKView) {
        backgroundColor = Palette.uiBackground
        rebuild()
    }

    private func rebuild() {
        removeAllChildren()
        let w = size.width
        let compact = size.height < 750          // SE-class screens
        let rowStep: CGFloat = compact ? 42 : 52
        let sectionGap: CGFloat = compact ? 22 : 30
        let top = size.height - (compact ? 46 : 70)

        addLabel("UPGRADE LAB", size: 26, color: Palette.player,
                 at: CGPoint(x: w / 2, y: top), bold: true)
        addLabel("◈ \(meta.shards)", size: 20, color: Palette.gem,
                 at: CGPoint(x: w / 2, y: top - 30), bold: true)

        var y = top - (compact ? 62 : 72)
        for kind in MetaUpgradeKind.allCases {
            let rank = meta.rank(of: kind)
            let maxed = rank >= kind.maxRank
            let cost = maxed ? nil : kind.cost(rank: rank)
            let affordable = cost.map { meta.shards >= $0 } ?? false

            let row = SKNode()
            row.name = "buy-\(kind.rawValue)"
            row.position = CGPoint(x: w / 2, y: y)
            addChild(row)

            let title = SKLabelNode(fontNamed: "Menlo-Bold")
            title.text = "\(kind.displayName)  \(String(repeating: "▰", count: rank))\(String(repeating: "▱", count: kind.maxRank - rank))"
            title.fontSize = 15
            title.fontColor = maxed ? Palette.gem : Palette.ui
            title.horizontalAlignmentMode = .left
            title.verticalAlignmentMode = .center
            title.position = CGPoint(x: -w / 2 + 24, y: 8)
            title.name = row.name
            row.addChild(title)

            let sub = SKLabelNode(fontNamed: "Menlo")
            sub.text = kind.blurb
            sub.fontSize = 11
            sub.fontColor = Palette.ui.withAlphaComponent(0.55)
            sub.horizontalAlignmentMode = .left
            sub.verticalAlignmentMode = .center
            sub.position = CGPoint(x: -w / 2 + 24, y: -10)
            sub.name = row.name
            row.addChild(sub)

            let price = SKLabelNode(fontNamed: "Menlo-Bold")
            price.text = maxed ? "MAX" : "◈ \(cost!)"
            price.fontSize = 15
            price.fontColor = maxed ? Palette.gem
                : (affordable ? Palette.player : Palette.ui.withAlphaComponent(0.35))
            price.horizontalAlignmentMode = .right
            price.verticalAlignmentMode = .center
            price.position = CGPoint(x: w / 2 - 24, y: 0)
            price.name = row.name
            row.addChild(price)

            y -= rowStep
        }

        // Cosmetics: shapes and trails.
        y -= 6
        addLabel("CORE SHAPE", size: 13, color: Palette.ui.withAlphaComponent(0.6),
                 at: CGPoint(x: w / 2, y: y))
        y -= sectionGap
        addOptionRow(names: shapeNames, unlocked: meta.unlockedShapes,
                     selected: meta.selectedShape, price: shapePrice,
                     prefix: "shape", y: y)
        y -= sectionGap + 14
        addLabel("TRAIL", size: 13, color: Palette.ui.withAlphaComponent(0.6),
                 at: CGPoint(x: w / 2, y: y))
        y -= sectionGap
        addOptionRow(names: trailNames, unlocked: meta.unlockedTrails,
                     selected: meta.selectedTrail, price: trailPrice,
                     prefix: "trail", y: y)

        // Overdrive selector.
        y -= sectionGap + 18
        if meta.victories > 0 {
            addLabel("OVERDRIVE", size: 13, color: Palette.enemyLow,
                     at: CGPoint(x: w / 2, y: y))
            y -= 30
            let unlockedTier = meta.unlockedOverdriveTier
            var x = w / 2 - CGFloat(min(unlockedTier, 5)) * 30 - 30
            for t in 0...min(unlockedTier, 5) {
                let label = SKLabelNode(fontNamed: "Menlo-Bold")
                label.text = t == 0 ? "BASE" : "OD\(t)"
                label.fontSize = 15
                label.fontColor = t == UserSelections.overdriveTier ? Palette.enemyLow : Palette.ui.withAlphaComponent(0.5)
                label.verticalAlignmentMode = .center
                label.position = CGPoint(x: x, y: y)
                label.name = "od-\(t)"
                addChild(label)
                x += 64
            }
            y -= 34
        }

        // Stats + back, anchored to the bottom (never overlaps content rows).
        let mins = Int(meta.bestSurvivalSeconds) / 60
        let secs = Int(meta.bestSurvivalSeconds) % 60
        addLabel(String(format: "BEST %d:%02d   ✕ %d   RUNS %d   WINS %d",
                        mins, secs, meta.bestKills, meta.totalRuns, meta.victories),
                 size: 12, color: Palette.ui.withAlphaComponent(0.6),
                 at: CGPoint(x: w / 2, y: compact ? 66 : 90))

        let back = SKLabelNode(fontNamed: "Menlo-Bold")
        back.text = "▶ ENTER THE HORDE"
        back.fontSize = 20
        back.fontColor = Palette.player
        back.verticalAlignmentMode = .center
        back.position = CGPoint(x: w / 2, y: compact ? 34 : 48)
        back.name = "back"
        addChild(back)
    }

    private func addLabel(_ text: String, size: CGFloat, color: UIColor,
                          at point: CGPoint, bold: Bool = false) {
        let label = SKLabelNode(fontNamed: bold ? "Menlo-Bold" : "Menlo")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.position = point
        addChild(label)
    }

    private func addOptionRow(names: [String], unlocked: [Int], selected: Int,
                              price: Int, prefix: String, y: CGFloat) {
        let w = size.width
        let step = (w - 48) / CGFloat(names.count)
        for (i, name) in names.enumerated() {
            let owned = unlocked.contains(i)
            let label = SKLabelNode(fontNamed: "Menlo-Bold")
            label.text = owned ? (i == selected ? "▣ \(name)" : "▢ \(name)") : "◈\(price) \(name)"
            label.fontSize = 12
            label.fontColor = owned
                ? (i == selected ? Palette.gem : Palette.ui.withAlphaComponent(0.7))
                : Palette.ui.withAlphaComponent(0.35)
            label.verticalAlignmentMode = .center
            label.position = CGPoint(x: 24 + step * (CGFloat(i) + 0.5), y: y)
            label.name = "\(prefix)-\(i)"
            addChild(label)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        for node in nodes(at: touch.location(in: self)) {
            guard let name = node.name else { continue }
            if name == "back" {
                SaveStore.save(meta)
                let scene = GameScene(size: size)
                scene.scaleMode = .resizeFill
                view?.presentScene(scene, transition: .fade(withDuration: 0.3))
                return
            }
            if name.hasPrefix("buy-"), let raw = Int(name.dropFirst(4)),
               let kind = MetaUpgradeKind(rawValue: raw) {
                if meta.buy(kind) {
                    SaveStore.save(meta)
                    rebuild()
                }
                return
            }
            if name.hasPrefix("shape-"), let i = Int(name.dropFirst(6)) {
                selectOrBuy(index: i, unlocked: &meta.unlockedShapes,
                            selected: &meta.selectedShape, price: shapePrice)
                return
            }
            if name.hasPrefix("trail-"), let i = Int(name.dropFirst(6)) {
                selectOrBuy(index: i, unlocked: &meta.unlockedTrails,
                            selected: &meta.selectedTrail, price: trailPrice)
                return
            }
            if name.hasPrefix("od-"), let t = Int(name.dropFirst(3)) {
                UserSelections.overdriveTier = t
                rebuild()
                return
            }
        }
    }

    private func selectOrBuy(index: Int, unlocked: inout [Int],
                             selected: inout Int, price: Int) {
        if unlocked.contains(index) {
            selected = index
        } else if meta.shards >= price {
            meta.shards -= price
            unlocked.append(index)
            selected = index
        } else {
            return
        }
        SaveStore.save(meta)
        rebuild()
    }
}

/// Session-scoped selections that aren't part of the persistent save.
enum UserSelections {
    static var overdriveTier = 0
}
