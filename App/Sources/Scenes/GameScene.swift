import SpriteKit
import NeonHordeCore

/// The gameplay scene: owns the deterministic World, steps it on a fixed
/// 60 Hz accumulator, and syncs pooled sprites to world state each frame.
final class GameScene: SKScene {
    // Simulation
    private var world = World(seed: 0x4E33304E)
    private var accumulator: Double = 0
    private var lastFrameTime: Double = 0

    // Render
    private var baker: TextureBaker!
    private var playerNode: SKSpriteNode!
    private var enemyPools: [EnemyKind: SpriteNodePool] = [:]
    private var projectilePool: SpriteNodePool!
    private var gemPool: SpriteNodePool!
    private var background: BackgroundRig!
    private let cameraNode = SKCameraNode()
    private var joystick: VirtualJoystick!
    private var hud: HUD!
    private var gameOver: GameOverOverlay!
    private var runIndex: UInt64 = 0

    // Perf telemetry (GOAL Phase 2 acceptance)
    private var perfFrames = 0
    private var perfTickMSTotal = 0.0
    private var perfTickMSMax = 0.0
    private var perfWindowStart = 0.0

    override func didMove(to view: SKView) {
        backgroundColor = Palette.uiBackground
        baker = TextureBaker(view: view)

        camera = cameraNode
        addChild(cameraNode)

        background = BackgroundRig(parent: self, baker: baker, viewSize: size)

        playerNode = SKSpriteNode(texture: baker.player)
        playerNode.zPosition = ZBand.player
        playerNode.blendMode = .add
        addChild(playerNode)

        for (i, kind) in EnemyKind.allCases.enumerated() {
            enemyPools[kind] = SpriteNodePool(
                texture: baker.enemyTextures[kind]!,
                capacity: Balance.enemyCap,
                zPosition: ZBand.enemies + CGFloat(i) * 0.1,
                parent: self
            )
        }

        projectilePool = SpriteNodePool(texture: baker.projectile,
                                        capacity: Balance.projectileCap,
                                        zPosition: ZBand.projectiles, parent: self)
        gemPool = SpriteNodePool(texture: baker.gem, capacity: Balance.gemCap,
                                 zPosition: ZBand.gems, parent: self)

        joystick = VirtualJoystick(parent: cameraNode, baker: baker)
        hud = HUD(parent: cameraNode, viewSize: size,
                  safeTop: view.safeAreaInsets.top)
        gameOver = GameOverOverlay(parent: cameraNode, viewSize: size)

        configureWorld()
    }

    private func configureWorld() {
        world.config.viewHalf = Vec2(Float(size.width) / 2, Float(size.height) / 2)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("STRESS") {
            world.config.directorEnabled = false
            world.config.combatEnabled = false
            world.spawnStressEnemies(500)
        }
        #if DEBUG
        if args.contains("ALMOSTDEAD") {   // fast, deterministic death-flow check
            world.player.hp = 1
        }
        #endif
    }

    private func restartRun() {
        runIndex += 1
        world = World(seed: 0x4E33304E &+ runIndex &* 0x9E3779B9)
        configureWorld()
        gameOver.hide()
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        if lastFrameTime == 0 {
            lastFrameTime = currentTime
            perfWindowStart = currentTime
        }
        var frameDT = currentTime - lastFrameTime
        lastFrameTime = currentTime
        frameDT = min(frameDT, 0.25)   // background/hitch guard

        accumulator += frameDT
        let step = Double(Balance.dt)
        var steps = 0
        let tickStart = CACurrentMediaTime()
        while accumulator >= step, steps < 5 {   // spiral-of-death clamp
            world.tick(WorldInput(move: joystick.vector))
            accumulator -= step
            steps += 1
        }
        if steps == 5 { accumulator = 0 }
        let tickMS = (CACurrentMediaTime() - tickStart) * 1000

        syncRender()
        recordPerf(currentTime: currentTime, tickMS: tickMS)
    }

    private func syncRender() {
        let p = world.player.pos
        playerNode.position = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))

        // Soft-lag camera follow.
        let target = playerNode.position
        let lag: CGFloat = 0.12
        cameraNode.position = CGPoint(
            x: cameraNode.position.x + (target.x - cameraNode.position.x) * lag,
            y: cameraNode.position.y + (target.y - cameraNode.position.y) * lag
        )
        background.update(cameraPosition: cameraNode.position, viewSize: size)

        for pool in enemyPools.values { pool.beginFrame() }
        for e in world.enemies {
            let rotation: CGFloat
            switch e.kind {
            case .dart, .weaver:
                rotation = CGFloat(atan2f(e.vel.y, e.vel.x)) - .pi / 2
            case .brick, .splitter, .spitter:
                rotation = CGFloat(e.phase) * 0.3
            }
            enemyPools[e.kind]?.place(x: CGFloat(e.pos.x), y: CGFloat(e.pos.y),
                                      rotation: rotation)
        }
        for pool in enemyPools.values { pool.endFrame() }

        projectilePool.beginFrame()
        for p in world.projectiles {
            projectilePool.place(x: CGFloat(p.pos.x), y: CGFloat(p.pos.y))
        }
        projectilePool.endFrame()

        gemPool.beginFrame()
        for g in world.gems {
            gemPool.place(x: CGFloat(g.pos.x), y: CGFloat(g.pos.y))
        }
        gemPool.endFrame()

        // Player i-frame flicker = readable invulnerability.
        playerNode.alpha = world.player.iFrames > 0
            ? (Int(world.tickIndex) % 6 < 3 ? 0.35 : 1.0)
            : 1.0

        hud.update(world: world)
        for event in world.events {
            if case .playerDied = event {
                gameOver.show(world: world)
                #if DEBUG
                // AUTOREPLAY drives the same restart path a tap uses, so the
                // death→restart loop is screenshot-verifiable headlessly.
                if ProcessInfo.processInfo.arguments.contains("AUTOREPLAY") {
                    run(.sequence([.wait(forDuration: 2), .run { [weak self] in
                        self?.restartRun()
                    }]))
                }
                #endif
            }
        }
    }

    private func recordPerf(currentTime: Double, tickMS: Double) {
        perfFrames += 1
        perfTickMSTotal += tickMS
        perfTickMSMax = max(perfTickMSMax, tickMS)
        let window = currentTime - perfWindowStart
        guard window >= 5 else { return }
        let fps = Double(perfFrames) / window
        let avgTick = perfTickMSTotal / Double(perfFrames)
        print(String(format: "PERF avg_fps=%.1f avg_tick_ms=%.3f max_tick_ms=%.2f entities=%d",
                     fps, avgTick, perfTickMSMax, world.enemies.count))
        perfFrames = 0
        perfTickMSTotal = 0
        perfTickMSMax = 0
        perfWindowStart = currentTime
    }

    // MARK: - Touch → joystick (camera space)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if gameOver.isVisible {
            restartRun()
            return
        }
        for t in touches {
            joystick.touchBegan(t, location: t.location(in: cameraNode))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            joystick.touchMoved(t, location: t.location(in: cameraNode))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { joystick.touchEnded(t) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches { joystick.touchEnded(t) }
    }
}
