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
    private var minePool: SpriteNodePool!
    private var bladePool: SpriteNodePool!
    private var beamNodes: [SKSpriteNode] = []
    private var gemPool: SpriteNodePool!
    private var effects: EffectsRig!
    private var bossNode: SKSpriteNode!
    private var bossBeamNodes: [SKSpriteNode] = []
    private var enemyShotPool: SpriteNodePool!
    private var chestPool: SpriteNodePool!
    private var background: BackgroundRig!
    private let cameraNode = SKCameraNode()
    private var joystick: VirtualJoystick!
    private var hud: HUD!
    private var gameOver: GameOverOverlay!
    private var draftOverlay: DraftOverlay!
    private var runIndex: UInt64 = 0
    private var demoWeaponMode = false

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
        minePool = SpriteNodePool(texture: baker.mine, capacity: 40,
                                  zPosition: ZBand.projectiles + 0.1, parent: self)
        bladePool = SpriteNodePool(texture: baker.blade, capacity: 8,
                                   zPosition: ZBand.projectiles + 0.2, parent: self)
        gemPool = SpriteNodePool(texture: baker.gem, capacity: Balance.gemCap,
                                 zPosition: ZBand.gems, parent: self)
        for _ in 0..<2 {   // prism beam (1-2 beams)
            let b = SKSpriteNode(texture: baker.beamSegment)
            b.anchorPoint = CGPoint(x: 0, y: 0.5)
            b.blendMode = .add
            b.zPosition = ZBand.projectiles + 0.3
            b.isHidden = true
            addChild(b)
            beamNodes.append(b)
        }
        effects = EffectsRig(parent: self)

        bossNode = SKSpriteNode(texture: baker.bossTexture)
        bossNode.zPosition = ZBand.enemies + 5
        bossNode.blendMode = .add
        bossNode.isHidden = true
        addChild(bossNode)
        for _ in 0..<2 {   // PRIME's storm-phase beams
            let b = SKSpriteNode(texture: baker.beamSegment)
            b.anchorPoint = CGPoint(x: 0, y: 0.5)
            b.blendMode = .add
            b.zPosition = ZBand.enemies + 5.1
            b.color = Palette.enemyLow
            b.colorBlendFactor = 0.7
            b.isHidden = true
            addChild(b)
            bossBeamNodes.append(b)
        }
        enemyShotPool = SpriteNodePool(texture: baker.enemyShot,
                                       capacity: Balance.enemyShotCap,
                                       zPosition: ZBand.projectiles + 0.4, parent: self)
        chestPool = SpriteNodePool(texture: baker.chest, capacity: 8,
                                   zPosition: ZBand.gems + 0.5, parent: self)

        joystick = VirtualJoystick(parent: cameraNode, baker: baker)
        hud = HUD(parent: cameraNode, viewSize: size,
                  safeTop: view.safeAreaInsets.top)
        gameOver = GameOverOverlay(parent: cameraNode, viewSize: size)
        draftOverlay = DraftOverlay(parent: cameraNode, viewSize: size)

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
        // BOSSDEMO: strong build, clock at 8:57 — PRIME arrives in seconds.
        if args.contains("BOSSDEMO") {
            world.demoStrongLoadout()
            world.demoJumpClock(to: 537)
            world.config.draftsEnabled = false      // unattended showcase
            world.config.playerInvulnerable = true  // stationary rig must outlast PRIME
        }
        // DEMO_WEAPON=<n>: showcase one weapon against a converging swarm.
        if let arg = args.first(where: { $0.hasPrefix("DEMO_WEAPON=") }),
           let n = Int(arg.dropFirst("DEMO_WEAPON=".count)),
           let kind = WeaponKind(rawValue: n) {
            world.config.directorEnabled = false
            world.config.playerInvulnerable = true
            world.config.draftsEnabled = false
            world.demoLoadout(weapon: kind, level: 4)
            world.spawnStressEnemies(70)
            demoWeaponMode = true
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
            handleEvents()
        }
        if steps == 5 { accumulator = 0 }
        let tickMS = (CACurrentMediaTime() - tickStart) * 1000

        if demoWeaponMode, world.enemies.count < 30 {
            world.spawnStressEnemies(40)   // keep the showcase fed
        }

        syncRender()
        effects.update(dt: CGFloat(frameDT))
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
                                      rotation: rotation,
                                      scale: e.elite ? CGFloat(Balance.eliteScale) : 1)
        }
        for pool in enemyPools.values { pool.endFrame() }

        enemyShotPool.beginFrame()
        for s in world.enemyShots {
            enemyShotPool.place(x: CGFloat(s.pos.x), y: CGFloat(s.pos.y))
        }
        enemyShotPool.endFrame()

        chestPool.beginFrame()
        for c in world.chests where !c.collected {
            let pulse = 1 + 0.15 * sin(CGFloat(world.time) * 4)
            chestPool.place(x: CGFloat(c.pos.x), y: CGFloat(c.pos.y),
                            rotation: 0, scale: pulse)
        }
        chestPool.endFrame()

        syncBoss()

        projectilePool.beginFrame()
        minePool.beginFrame()
        for p in world.projectiles {
            if p.mine {
                minePool.place(x: CGFloat(p.pos.x), y: CGFloat(p.pos.y),
                               rotation: CGFloat(world.time) * 1.5)
            } else {
                projectilePool.place(x: CGFloat(p.pos.x), y: CGFloat(p.pos.y))
            }
        }
        projectilePool.endFrame()
        minePool.endFrame()

        syncWeaponVisuals()

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
    }

    private func syncBoss() {
        guard let boss = world.boss else {
            bossNode.isHidden = true
            for b in bossBeamNodes { b.isHidden = true }
            return
        }
        bossNode.isHidden = false
        bossNode.position = CGPoint(x: CGFloat(boss.pos.x), y: CGFloat(boss.pos.y))
        bossNode.zRotation = CGFloat(boss.spinAngle)
        // Telegraphs read through scale: swell before a dash, pulse in storm.
        let phaseScale: CGFloat = boss.chargeState == 1 ? 1.18 : 1.0
        bossNode.setScale(phaseScale)

        let storm = boss.phase == .storm
        for (k, node) in bossBeamNodes.enumerated() {
            node.isHidden = !storm
            guard storm else { continue }
            let a = boss.spinAngle + Float(k) * .pi
            node.position = bossNode.position
            node.zRotation = CGFloat(a)
            node.size = CGSize(width: 700, height: CGFloat(Balance.bossBeamHalfWidth) * 2)
        }
    }

    /// Continuous weapon visuals derived from world state each frame.
    private func syncWeaponVisuals() {
        bladePool.beginFrame()
        let bladeLevel = world.loadout.level(of: .orbitBlades)
        if bladeLevel > 0 {
            let p = Balance.weapon(.orbitBlades, level: bladeLevel, loadout: world.loadout)
            for k in 0..<p.count {
                let a = world.orbitAngle + Float(k) * (2 * .pi / Float(p.count))
                let bx = world.player.pos.x + cosApprox(a) * p.area
                let by = world.player.pos.y + sinApprox(a) * p.area
                bladePool.place(x: CGFloat(bx), y: CGFloat(by), rotation: CGFloat(a) + .pi)
            }
        }
        bladePool.endFrame()

        let beamLevel = world.loadout.level(of: .prismBeam)
        if beamLevel > 0 {
            let p = Balance.weapon(.prismBeam, level: beamLevel, loadout: world.loadout)
            for (k, node) in beamNodes.enumerated() {
                guard k < p.count else {
                    node.isHidden = true
                    continue
                }
                let a = world.beamAngle + Float(k) * .pi
                node.isHidden = false
                node.position = playerNode.position
                node.zRotation = CGFloat(a)
                node.size = CGSize(width: 500, height: CGFloat(p.area) * 2)
            }
        } else {
            for node in beamNodes { node.isHidden = true }
        }
    }

    /// World events → transient effects and overlay state changes.
    private func handleEvents() {
        for event in world.events {
            switch event {
            case .playerDied:
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
            case .draftOpened:
                if let draft = world.pendingDraft {
                    draftOverlay.show(draft: draft, world: world, baker: baker)
                }
            case .novaBurst(let center, let radius):
                effects.ring(at: CGPoint(x: CGFloat(center.x), y: CGFloat(center.y)),
                             texture: baker.ring, fromRadius: 20, toRadius: CGFloat(radius))
            case .mineExploded(let center, let radius):
                effects.ring(at: CGPoint(x: CGFloat(center.x), y: CGFloat(center.y)),
                             texture: baker.ring, fromRadius: 10, toRadius: CGFloat(radius),
                             ttl: 0.3, color: Palette.enemyHigh)
            case .railLance(let origin, let dir, let length):
                effects.beam(from: CGPoint(x: CGFloat(origin.x), y: CGFloat(origin.y)),
                             angle: CGFloat(atan2Approx(dir.y, dir.x)),
                             length: CGFloat(length), thickness: 14,
                             texture: baker.beamSegment, ttl: 0.25)
            case .chainArc(let points):
                effects.chain(points: points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                              texture: baker.beamSegment)
            case .victory:
                gameOver.showVictory(world: world)
            case .bossSpawned:
                // Arena-wipe shockwave sells the entrance.
                effects.ring(at: playerNode.position, texture: baker.ring,
                             fromRadius: 40, toRadius: 700, ttl: 0.8)
            default:
                break   // hits/kills/gems get their juice in Phase 7
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
        if draftOverlay.isVisible {
            if let touch = touches.first {
                let tapped = nodes(at: touch.location(in: self))
                if let index = draftOverlay.cardIndex(at: tapped) {
                    world.applyDraft(index)
                    draftOverlay.hide()
                    // Queued level-ups chain straight into the next draft.
                    if let next = world.pendingDraft {
                        draftOverlay.show(draft: next, world: world, baker: baker)
                    }
                }
            }
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
