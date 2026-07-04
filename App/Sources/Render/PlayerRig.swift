import SpriteKit
import NeonHordeCore

/// The hero's visual: animated character when ART sheets exist, the classic
/// glow-orb otherwise. Either way it carries the stage-evolution aura
/// (teal → violet → gold) required by GOAL AMENDMENT v3.
final class PlayerRig {
    enum State {
        case idle, run, attack, dead
    }

    let node: SKSpriteNode          // the visible body
    private let aura: SKSpriteNode
    private let art: ArtLibrary
    private var state: State = .idle
    private var frameClock: Double = 0
    private var attackHold: Double = 0
    private var deathFrame = 0
    private let fallbackTexture: SKTexture
    private let auraColors: [UIColor] = [
        Palette.player,
        UIColor(red: 0.72, green: 0.4, blue: 1.0, alpha: 1),
        UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1),
    ]

    init(parent: SKNode, art: ArtLibrary, baker: TextureBaker) {
        self.art = art
        fallbackTexture = baker.player
        node = SKSpriteNode(texture: art.playerIdle?.frames.first ?? baker.player)
        node.zPosition = ZBand.player
        if art.hasHero {
            node.blendMode = .alpha
            node.size = CGSize(width: 44, height: 88)   // character proportions
            node.anchorPoint = CGPoint(x: 0.5, y: 0.32)  // feet near collision center
        } else {
            node.blendMode = .add
        }
        aura = SKSpriteNode(texture: baker.ring)
        aura.blendMode = .add
        aura.zPosition = ZBand.player - 0.5
        aura.alpha = 0.5
        aura.setScale(0.5)
        node.addChild(aura)
        parent.addChild(node)
    }

    /// Trigger the sword-swing animation (called when weapons fire).
    func attack() {
        guard art.playerAttack != nil, state != .dead else { return }
        if state != .attack {
            state = .attack
            frameClock = 0
        }
        attackHold = 0.32
    }

    func die() {
        guard state != .dead else { return }
        state = .dead
        frameClock = 0
        deathFrame = 0
    }

    func reset() {
        state = .idle
        frameClock = 0
        node.alpha = 1
    }

    func update(dt: Double, world: World, moving: Bool) {
        // Position + facing.
        node.position = CGPoint(x: CGFloat(world.player.pos.x),
                                y: CGFloat(world.player.pos.y))
        if art.hasHero, abs(world.player.facing.x) > 0.05 {
            node.xScale = world.player.facing.x < 0 ? -abs(node.xScale) : abs(node.xScale)
        }

        // Stage aura evolution.
        let stage = min(world.stage, auraColors.count - 1)
        aura.color = auraColors[stage]
        aura.colorBlendFactor = 1
        aura.alpha = 0.35 + CGFloat(stage) * 0.15
        aura.setScale(0.5 + CGFloat(stage) * 0.12)
        aura.zRotation += CGFloat(dt) * 0.8

        guard art.hasHero else { return }   // orb mode: nothing else to animate

        // State transitions.
        if world.state == .dead && state != .dead {
            die()
        }
        if state == .attack {
            attackHold -= dt
            if attackHold <= 0 { state = moving ? .run : .idle }
        } else if state != .dead {
            state = moving ? .run : .idle
        }

        // Frame advance.
        frameClock += dt
        switch state {
        case .idle:
            setFrame(art.playerIdle, loop: true)
        case .run:
            setFrame(art.playerRun, loop: true)
        case .attack:
            setFrame(art.playerAttack, loop: true)
        case .dead:
            if let anim = art.playerDeath {
                let idx = min(Int(frameClock * anim.fps), anim.frames.count - 1)
                node.texture = anim.frames[idx]
            }
        }
    }

    private func setFrame(_ anim: ArtLibrary.AnimatedSprite?, loop: Bool) {
        guard let anim else { return }
        let idx = Int(frameClock * anim.fps) % anim.frames.count
        node.texture = anim.frames[idx]
    }
}
