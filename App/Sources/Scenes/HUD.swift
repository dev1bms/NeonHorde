import SpriteKit
import NeonHordeCore

/// Camera-space HUD: HP bar, XP bar, run timer, kill counter, level badge.
/// Labels here are few and change at most once per frame — SKLabelNode is
/// acceptable (the SKLabelNode ban is for pooled damage numbers).
final class HUD {
    private let root = SKNode()
    private let hpFill: SKSpriteNode
    private let xpFill: SKSpriteNode
    private let timerLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let killsLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let levelLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let hpWidth: CGFloat = 150
    private let bossBar: SKSpriteNode
    private let bossBarBG: SKSpriteNode
    private let bossLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    private var lastTimerText = ""
    private var lastKills = -1
    private var lastLevel = -1

    init(parent: SKNode, viewSize: CGSize, safeTop: CGFloat) {
        root.zPosition = ZBand.hud
        parent.addChild(root)

        let top = viewSize.height / 2 - safeTop - 16

        let hpBG = SKSpriteNode(color: Palette.ui.withAlphaComponent(0.15),
                                size: CGSize(width: hpWidth, height: 8))
        hpBG.position = CGPoint(x: -viewSize.width / 2 + 20 + hpWidth / 2, y: top)
        root.addChild(hpBG)

        hpFill = SKSpriteNode(color: Palette.player,
                              size: CGSize(width: hpWidth, height: 8))
        hpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        hpFill.position = CGPoint(x: -viewSize.width / 2 + 20, y: top)
        root.addChild(hpFill)

        let xpBG = SKSpriteNode(color: Palette.ui.withAlphaComponent(0.12),
                                size: CGSize(width: viewSize.width - 40, height: 4))
        xpBG.position = CGPoint(x: 0, y: top - 18)
        root.addChild(xpBG)

        xpFill = SKSpriteNode(color: Palette.gem,
                              size: CGSize(width: viewSize.width - 40, height: 4))
        xpFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        xpFill.position = CGPoint(x: -(viewSize.width - 40) / 2, y: top - 18)
        xpFill.xScale = 0
        root.addChild(xpFill)

        timerLabel.fontSize = 22
        timerLabel.fontColor = Palette.ui
        timerLabel.position = CGPoint(x: 0, y: top - 8)
        timerLabel.verticalAlignmentMode = .center
        root.addChild(timerLabel)

        killsLabel.fontSize = 15
        killsLabel.fontColor = Palette.enemyLow
        killsLabel.horizontalAlignmentMode = .right
        killsLabel.verticalAlignmentMode = .center
        killsLabel.position = CGPoint(x: viewSize.width / 2 - 20, y: top)
        root.addChild(killsLabel)

        levelLabel.fontSize = 15
        levelLabel.fontColor = Palette.gem
        levelLabel.horizontalAlignmentMode = .right
        levelLabel.verticalAlignmentMode = .center
        levelLabel.position = CGPoint(x: viewSize.width / 2 - 20, y: top - 24)
        root.addChild(levelLabel)

        // Pause button (hit-target name checked by GameScene).
        let pause = SKLabelNode(fontNamed: "Menlo-Bold")
        pause.text = "❚❚"
        pause.fontSize = 17
        pause.fontColor = Palette.ui.withAlphaComponent(0.7)
        pause.verticalAlignmentMode = .center
        pause.horizontalAlignmentMode = .right
        pause.position = CGPoint(x: viewSize.width / 2 - 20, y: top - 52)
        pause.name = "pauseButton"
        root.addChild(pause)

        // PRIME bar — hidden until the finale.
        let bossWidth = viewSize.width - 80
        bossBarBG = SKSpriteNode(color: Palette.ui.withAlphaComponent(0.15),
                                 size: CGSize(width: bossWidth, height: 10))
        bossBarBG.position = CGPoint(x: 0, y: top - 44)
        bossBarBG.isHidden = true
        root.addChild(bossBarBG)
        bossBar = SKSpriteNode(color: Palette.enemyLow,
                               size: CGSize(width: bossWidth, height: 10))
        bossBar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bossBar.position = CGPoint(x: -bossWidth / 2, y: top - 44)
        bossBar.isHidden = true
        root.addChild(bossBar)
        bossLabel.text = "P R I M E"
        bossLabel.fontSize = 13
        bossLabel.fontColor = Palette.enemyLow
        bossLabel.verticalAlignmentMode = .center
        bossLabel.position = CGPoint(x: 0, y: top - 60)
        bossLabel.isHidden = true
        root.addChild(bossLabel)
    }

    func update(world: World) {
        hpFill.xScale = CGFloat(max(0, world.player.hp / world.player.maxHP))
        let need = Balance.xpToNext(level: world.player.level)
        xpFill.xScale = CGFloat(max(0, min(1, world.player.xp / need)))

        let t = Int(world.time)
        let text = String(format: "%d:%02d", t / 60, t % 60)
        if text != lastTimerText {
            timerLabel.text = text
            lastTimerText = text
        }
        if world.kills != lastKills {
            killsLabel.text = "✕ \(world.kills)"
            lastKills = world.kills
        }
        if world.player.level != lastLevel {
            levelLabel.text = "LV \(world.player.level)"
            lastLevel = world.player.level
        }

        if let boss = world.boss {
            bossBarBG.isHidden = false
            bossBar.isHidden = false
            bossLabel.isHidden = false
            bossBar.xScale = CGFloat(max(0, boss.hp / boss.maxHP))
        } else {
            bossBarBG.isHidden = true
            bossBar.isHidden = true
            bossLabel.isHidden = true
        }
    }
}
