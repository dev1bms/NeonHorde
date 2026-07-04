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
    private var art: ArtLibrary!
    private var playerRig: PlayerRig!
    private var playerNode: SKSpriteNode { playerRig.node }
    private var propsRig: PropsRig!
    private var ambientTint: SKSpriteNode!
    private var prevPlayerPos = CGPoint.zero
    private var prevProjectileCount = 0
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
    private var pauseOverlay: PauseOverlay!
    private var isPaused2 = false   // "paused" collides with SKNode.isPaused
    private var menuOverlay: MenuOverlay!
    private var attractMode = false
    private var wasPlayRequested = false
    private var attractBot = KitingBot(seed: 7)
    private var runIndex: UInt64 = 0
    private var demoWeaponMode = false
    private var meta = MetaState()
    private var runBanked = false

    // Juice state (GOAL §4)
    private var damageNumbers: DamageNumberRig!
    private var trailEmitter: SKEmitterNode!
    private var shake: CGFloat = 0            // decaying screen-shake amplitude
    private var hitStopUntil: Double = 0      // wall-clock freeze window
    private var deathSlowMoUntil: Double = 0

    // Perf telemetry (GOAL Phase 2 acceptance)
    private var perfFrames = 0
    private var perfTickMSTotal = 0.0
    private var perfTickMSMax = 0.0
    private var perfWindowStart = 0.0

    override func didMove(to view: SKView) {
        backgroundColor = Palette.uiBackground
        meta = SaveStore.load()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("GRANTSHARDS") {
            meta.shards += 500
            SaveStore.save(meta)
        }
        #endif
        baker = TextureBaker(view: view, playerShape: meta.selectedShape)
        art = ArtLibrary()

        camera = cameraNode
        addChild(cameraNode)

        background = BackgroundRig(parent: self, baker: baker, art: art, viewSize: size)
        propsRig = PropsRig(parent: self, art: art)
        playerRig = PlayerRig(parent: self, art: art, baker: baker)

        // Stage ambience tint over everything but the HUD.
        ambientTint = SKSpriteNode(color: .clear,
                                   size: CGSize(width: size.width * 2, height: size.height * 2))
        ambientTint.zPosition = ZBand.effects + 5
        ambientTint.alpha = 0
        cameraNode.addChild(ambientTint)

        for (i, kind) in EnemyKind.allCases.enumerated() {
            let artFrames = art.monsterFrames[kind]
            let pool = SpriteNodePool(
                texture: artFrames?.first ?? baker.enemyTextures[kind]!,
                capacity: Balance.enemyCap,
                zPosition: ZBand.enemies + CGFloat(i) * 0.1,
                blendMode: artFrames != nil ? .alpha : .add,
                parent: self
            )
            enemyPools[kind] = pool
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

        bossNode = SKSpriteNode(texture: art.bossFrames?.first ?? baker.bossTexture)
        bossNode.zPosition = ZBand.enemies + 5
        bossNode.blendMode = art.bossFrames != nil ? .alpha : .add
        if art.bossFrames != nil {
            bossNode.size = CGSize(width: CGFloat(Balance.bossRadius) * 3.2,
                                   height: CGFloat(Balance.bossRadius) * 4.8)
        }
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
        enemyShotPool = SpriteNodePool(texture: art.monsterShot ?? baker.enemyShot,
                                       capacity: Balance.enemyShotCap,
                                       zPosition: ZBand.projectiles + 0.4, parent: self)
        chestPool = SpriteNodePool(texture: baker.chest, capacity: 8,
                                   zPosition: ZBand.gems + 0.5, parent: self)

        damageNumbers = DamageNumberRig(parent: self, baker: baker)

        // Player trail — pure code emitter, tinted by the equipped cosmetic.
        let trailColors = [Palette.player, Palette.enemyLow, Palette.gem,
                           UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)]
        trailEmitter = SKEmitterNode()
        trailEmitter.particleTexture = baker.projectile
        trailEmitter.particleBirthRate = 34
        trailEmitter.particleLifetime = 0.45
        trailEmitter.particleAlpha = 0.5
        trailEmitter.particleAlphaSpeed = -1.2
        trailEmitter.particleScale = 0.7
        trailEmitter.particleScaleSpeed = -1.4
        trailEmitter.particleColor = trailColors[min(meta.selectedTrail, trailColors.count - 1)]
        trailEmitter.particleColorBlendFactor = 1
        trailEmitter.particleBlendMode = .add
        trailEmitter.targetNode = self          // particles stay in world space
        trailEmitter.zPosition = ZBand.player - 1
        playerNode.addChild(trailEmitter)

        Haptics.shared.enabled = meta.hapticsOn
        AudioManager.shared.start(musicOn: meta.musicOn, sfxOn: meta.sfxOn)

        joystick = VirtualJoystick(parent: cameraNode, baker: baker)
        hud = HUD(parent: cameraNode, viewSize: size,
                  safeTop: view.safeAreaInsets.top)
        gameOver = GameOverOverlay(parent: cameraNode, viewSize: size)
        draftOverlay = DraftOverlay(parent: cameraNode, viewSize: size)
        pauseOverlay = PauseOverlay(parent: cameraNode, viewSize: size)
        menuOverlay = MenuOverlay(parent: cameraNode, viewSize: size)

        // Backgrounding (or any interruption's resign-active) auto-pauses.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.pauseGame()
        }

        configureWorld()
    }

    private func pauseGame() {
        guard world.state == .playing, !gameOver.isVisible,
              !draftOverlay.isVisible, !isPaused2 else { return }
        isPaused2 = true
        pauseOverlay.show(meta: meta)
    }

    private func configureWorld() {
        world = World(seed: world.rng.next(), meta: meta)   // reseed with meta applied
        world.config.viewHalf = Vec2(Float(size.width) / 2, Float(size.height) / 2)
        world.config.overdriveTier = UserSelections.overdriveTier
        runBanked = false
        let args = ProcessInfo.processInfo.arguments
        isDemoRun = args.contains("STRESS") || args.contains("BOSSDEMO")
            || args.contains { $0.hasPrefix("DEMO_WEAPON=") }

        // Menu = live attract mode: a bot plays behind the title (Phase 8).
        // Any demo/death harness boots straight into gameplay instead.
        let harnessRun = isDemoRun || args.contains("ALMOSTDEAD")
            || args.contains("SHARE_DEMO") || args.contains("STOREDRAFT")
        if !harnessRun, runIndex == 0, !wasPlayRequested {
            attractMode = true
            attractBot = KitingBot(seed: world.rng.next())
            menuOverlay?.show(meta: meta)
        }
        if args.contains("STRESS") {
            world.config.directorEnabled = false
            world.config.combatEnabled = false
            world.spawnStressEnemies(500)
        }
        // Demo/screenshot harness args — compiled into Release too (App Store
        // screenshots need a clean build without the DEBUG stats overlay).
        // They are inert unless explicitly passed at launch.
        if args.contains("SHARE_DEMO") {   // share-sheet screenshot harness
            run(.sequence([.wait(forDuration: 1.5), .run { [weak self] in
                guard let self, let view = self.view else { return }
                ShareCard.share(time: 154, kills: 218, level: 12, victory: false, from: view)
            }]))
        }
        if args.contains("ALMOSTDEAD") {   // fast, deterministic death-flow check
            world.player.hp = 1
            world.config.draftsEnabled = false   // unattended — a draft would freeze forever
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
        // STOREDRAFT: a real early run that opens the level-up draft at ~6s.
        if args.contains("STOREDRAFT") {
            world.demoStrongLoadout()
            run(.sequence([.wait(forDuration: 6), .run { [weak self] in
                self?.world.demoOpenDraft()
                self?.handleEvents()
            }]))
        }
    }

    private var isDemoRun = false

    private func restartRun() {
        runIndex += 1
        meta = SaveStore.load()   // pick up any Lab purchases
        configureWorld()
        gameOver.hide()
        playerRig?.reset()
        background?.setStage(0)
        ambientTint?.alpha = 0
    }

    private func bankRun(victory: Bool) {
        guard !runBanked, !isDemoRun, !attractMode else { return }
        runBanked = true
        meta.shards += world.shardsEarned
        meta.totalRuns += 1
        meta.bestKills = max(meta.bestKills, world.kills)
        meta.bestSurvivalSeconds = max(meta.bestSurvivalSeconds, world.time)
        if victory {
            meta.victories += 1
            meta.highestOverdriveBeaten = max(meta.highestOverdriveBeaten,
                                              world.config.overdriveTier)
        }
        SaveStore.save(meta)
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

        // Pause and hit-stop both freeze simulated time (GOAL §4).
        if isPaused2 || currentTime < hitStopUntil {
            accumulator = 0
        } else {
            accumulator += frameDT
        }
        let step = Double(Balance.dt)
        var steps = 0
        let tickStart = CACurrentMediaTime()
        while accumulator >= step, steps < 5 {   // spiral-of-death clamp
            if attractMode, let draft = world.pendingDraft {
                world.applyDraft(attractBot.pickDraft(draft, world: world))
            }
            let move = attractMode ? attractBot.move(world: world) : joystick.vector
            world.tick(WorldInput(move: move))
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
        let effectsDT = currentTime < deathSlowMoUntil ? frameDT * 0.3 : frameDT
        effects.update(dt: CGFloat(effectsDT))
        damageNumbers.update(dt: CGFloat(effectsDT))
        recordPerf(currentTime: currentTime, tickMS: tickMS)
    }

    private func syncRender() {
        let newPos = CGPoint(x: CGFloat(world.player.pos.x), y: CGFloat(world.player.pos.y))
        let moved = hypot(newPos.x - prevPlayerPos.x, newPos.y - prevPlayerPos.y) > 0.15
        prevPlayerPos = newPos
        if world.projectiles.count > prevProjectileCount {
            playerRig.attack()   // a weapon just fired — swing the sword
        }
        prevProjectileCount = world.projectiles.count
        playerRig.update(dt: 1.0 / 60.0, world: world, moving: moved)

        // Soft-lag camera follow + decaying screen shake.
        let target = playerNode.position
        let lag: CGFloat = 0.12
        var cam = CGPoint(
            x: cameraNode.position.x + (target.x - cameraNode.position.x) * lag,
            y: cameraNode.position.y + (target.y - cameraNode.position.y) * lag
        )
        if shake > 0.2 {
            let t = CACurrentMediaTime() * 47
            cam.x += CGFloat(sin(t * 1.13)) * shake
            cam.y += CGFloat(cos(t * 0.91)) * shake
            shake *= 0.88
        } else {
            shake = 0
        }
        cameraNode.position = cam
        background.update(cameraPosition: cameraNode.position, viewSize: size)
        propsRig.update(cameraPosition: cameraNode.position, viewSize: size)

        for pool in enemyPools.values { pool.beginFrame() }
        // Character mode: globally-synced 2-frame walk (batching stays intact),
        // attack frame near the player; monsters face their velocity.
        let walkFrame = Int(world.time * 5) % 2
        for e in world.enemies {
            let frames = art.monsterFrames[e.kind]
            var rotation: CGFloat = 0
            var texture: SKTexture?
            var size: CGSize?
            var flip = false
            if let frames {
                // Last frame = attack pose; the rest form the walk cycle
                // (sheets may carry 2..4 frames depending on slicing quality).
                let close = e.pos.distanceSquared(to: world.player.pos) < 90 * 90
                let walkCount = max(1, frames.count - 1)
                texture = frames[close ? frames.count - 1 : walkFrame % walkCount]
                let d = CGFloat(e.radius) * 5.0   // character art reads larger than hit circles
                size = CGSize(width: d, height: d)
                flip = e.vel.x > 0.5   // art faces LEFT; flip when moving right
            } else {
                switch e.kind {
                case .dart, .weaver:
                    rotation = CGFloat(atan2f(e.vel.y, e.vel.x)) - .pi / 2
                case .brick, .splitter, .spitter:
                    rotation = CGFloat(e.phase) * 0.3
                }
            }
            let scale = e.elite ? CGFloat(Balance.eliteScale) : 1
            let node = enemyPools[e.kind]?.place(
                x: CGFloat(e.pos.x), y: CGFloat(e.pos.y), rotation: rotation,
                scale: scale, texture: texture, size: size)
            if flip { node?.xScale = -scale }
            // White hit-flash while the enemy's flash timer runs (GOAL §4).
            if e.flash > 0 {
                node?.color = .white
                node?.colorBlendFactor = 0.85
            } else {
                node?.colorBlendFactor = 0
            }
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
        if let frames = art.bossFrames {
            // Character boss: idle / slam-windup / roar frames, facing flip.
            var frame: Int
            if boss.chargeState == 1 { frame = 1 }
            else if boss.phase == .storm { frame = 2 }
            else { frame = Int(world.time * 2) % 2 == 0 ? 0 : 2 }
            frame = min(frame, frames.count - 1)
            bossNode.texture = frames[frame]
            bossNode.zRotation = 0
        } else {
            bossNode.zRotation = CGFloat(boss.spinAngle)
        }
        // Telegraphs read through scale: swell before a dash, pulse in storm.
        let phaseScale: CGFloat = boss.chargeState == 1 ? 1.18 : 1.0
        bossNode.setScale(phaseScale)
        if art.bossFrames != nil, (world.player.pos.x - boss.pos.x) > 0 {
            bossNode.xScale = -phaseScale   // art faces LEFT; mirror toward player
        }

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

    /// World events → juice, audio, haptics, and overlay state changes.
    private func handleEvents() {
        for event in world.events {
            if let haptic = HapticMapping.haptic(for: event) {
                Haptics.shared.play(haptic)
            }
            switch event {
            case .playerDied where attractMode, .victory where attractMode:
                configureWorld()   // the menu's demo run just loops forever
                return
            case .playerDied:
                bankRun(victory: false)
                shake = 14
                deathSlowMoUntil = CACurrentMediaTime() + 0.55
                effects.ring(at: playerNode.position, texture: baker.ring,
                             fromRadius: 10, toRadius: 260, ttl: 0.55,
                             color: Palette.enemyLow)
                AudioManager.shared.play(.explosion)
                run(.sequence([.wait(forDuration: 0.55), .run { [weak self] in
                    guard let self, self.world.state == .dead else { return }
                    self.gameOver.show(world: self.world)
                    self.gameOver.setShardsEarned(self.world.shardsEarned)
                }]))
                #if DEBUG
                // AUTOREPLAY drives the same restart path a tap uses, so the
                // death→restart loop is screenshot-verifiable headlessly.
                if ProcessInfo.processInfo.arguments.contains("AUTOREPLAY") {
                    run(.sequence([.wait(forDuration: 2), .run { [weak self] in
                        self?.restartRun()
                    }]))
                }
                #endif
            case .playerHit:
                shake = max(shake, 6)
                AudioManager.shared.play(.hit)
            case .enemyDied(let pos, _):
                _ = pos
                AudioManager.shared.play(.laser)   // kill feedback, throttled inside
            case .gemCollected:
                AudioManager.shared.play(.pickup)
            case .leveledUp:
                effects.ring(at: playerNode.position, texture: baker.ring,
                             fromRadius: 16, toRadius: 130, ttl: 0.4)
                AudioManager.shared.play(.levelup)
            case .revived:
                shake = 10
                effects.ring(at: playerNode.position, texture: baker.ring,
                             fromRadius: 20, toRadius: 320, ttl: 0.7, color: Palette.gem)
                AudioManager.shared.play(.revive)
            case .draftOpened:
                guard !attractMode else { break }   // bot picks silently in attract
                AudioManager.shared.play(.uitick)
                if let draft = world.pendingDraft {
                    draftOverlay.show(draft: draft, world: world, baker: baker)
                }
            case .novaBurst(let center, let radius):
                effects.ring(at: CGPoint(x: CGFloat(center.x), y: CGFloat(center.y)),
                             texture: baker.ring, fromRadius: 20, toRadius: CGFloat(radius))
            case .mineExploded(let center, let radius):
                shake = max(shake, 3)
                effects.ring(at: CGPoint(x: CGFloat(center.x), y: CGFloat(center.y)),
                             texture: baker.ring, fromRadius: 10, toRadius: CGFloat(radius),
                             ttl: 0.3, color: Palette.enemyHigh)
                AudioManager.shared.play(.explosion)
            case .railLance(let origin, let dir, let length):
                effects.beam(from: CGPoint(x: CGFloat(origin.x), y: CGFloat(origin.y)),
                             angle: CGFloat(atan2Approx(dir.y, dir.x)),
                             length: CGFloat(length), thickness: 14,
                             texture: baker.beamSegment, ttl: 0.25)
            case .chainArc(let points):
                effects.chain(points: points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) },
                              texture: baker.beamSegment)
            case .damageDealt(let pos, let amount):
                damageNumbers.spawn(amount: amount,
                                    at: CGPoint(x: CGFloat(pos.x), y: CGFloat(pos.y) + 14))
            case .eliteSpawned:
                shake = max(shake, 4)
                AudioManager.shared.play(.bossroar)
            case .chestCollected(let pos):
                effects.ring(at: CGPoint(x: CGFloat(pos.x), y: CGFloat(pos.y)),
                             texture: baker.ring, fromRadius: 10, toRadius: 90, ttl: 0.4,
                             color: UIColor(red: 1, green: 0.85, blue: 0.3, alpha: 1))
                AudioManager.shared.play(.levelup)
            case .bossSpawned:
                shake = 16
                hitStopUntil = CACurrentMediaTime() + 0.04
                effects.ring(at: playerNode.position, texture: baker.ring,
                             fromRadius: 40, toRadius: 700, ttl: 0.8)
                showBossBanner()
                AudioManager.shared.play(.bossroar)
                AudioManager.shared.setBossMode(true)
            case .bossPhase:
                shake = 10
                hitStopUntil = CACurrentMediaTime() + 0.04
                AudioManager.shared.play(.bossroar)
            case .bossDied:
                shake = 18
                hitStopUntil = CACurrentMediaTime() + 0.08
                AudioManager.shared.setBossMode(false)
                AudioManager.shared.play(.explosion)
            case .victory:
                bankRun(victory: true)
                gameOver.showVictory(world: world)
                gameOver.setShardsEarned(world.shardsEarned)
            case .chestDropped:
                break
            case .stageAdvanced(let s):
                let names = ["DAWN WOODS", "DEEP FOREST", "CURSED WOODS"]
                let tints: [UIColor] = [.clear,
                                        UIColor(red: 0.1, green: 0.35, blue: 0.4, alpha: 1),
                                        UIColor(red: 0.35, green: 0.08, blue: 0.05, alpha: 1)]
                background.setStage(s)
                ambientTint.color = tints[min(s, tints.count - 1)]
                ambientTint.alpha = s == 0 ? 0 : 0.16
                showBanner(names[min(s, names.count - 1)], color: Palette.gem)
                effects.ring(at: playerNode.position, texture: baker.ring,
                             fromRadius: 20, toRadius: 420, ttl: 0.7, color: Palette.gem)
                shake = max(shake, 6)
                AudioManager.shared.play(.levelup)
            }
        }
    }

    private func showBossBanner() {
        showBanner("P R I M E", color: Palette.enemyLow)
    }

    /// Full-screen announcement banner — one-shot SKAction, not a hot path.
    private func showBanner(_ text: String, color: UIColor) {
        let banner = SKLabelNode(fontNamed: "Menlo-Bold")
        banner.text = text
        banner.fontSize = 44
        banner.fontColor = color
        banner.position = CGPoint(x: 0, y: 120)
        banner.zPosition = ZBand.hud + 5
        banner.alpha = 0
        banner.setScale(1.6)
        cameraNode.addChild(banner)
        banner.run(.sequence([
            .group([.fadeIn(withDuration: 0.25), .scale(to: 1.0, duration: 0.25)]),
            .wait(forDuration: 1.4),
            .fadeOut(withDuration: 0.5),
            .removeFromParent(),
        ]))
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
        if attractMode {
            guard let touch = touches.first else { return }
            switch menuOverlay.control(at: nodes(at: touch.location(in: self))) {
            case "menu-lab":
                let lab = UpgradeLabScene(size: size)
                lab.scaleMode = .resizeFill
                view?.presentScene(lab, transition: .fade(withDuration: 0.3))
            default:   // PLAY — anywhere else on screen also starts
                attractMode = false
                wasPlayRequested = true
                menuOverlay.hide()
                restartRun()
            }
            return
        }
        if pauseOverlay.isVisible {
            guard let touch = touches.first else { return }
            switch pauseOverlay.control(at: nodes(at: touch.location(in: self))) {
            case "resume":
                isPaused2 = false
                pauseOverlay.hide()
            case "abandon":
                isPaused2 = false
                pauseOverlay.hide()
                world.abandonRun()
                bankRun(victory: false)
                gameOver.show(world: world)
                gameOver.setShardsEarned(world.shardsEarned)
            case "toggle-music":
                meta.musicOn.toggle()
                SaveStore.save(meta)
                AudioManager.shared.setMusicOn(meta.musicOn)
                pauseOverlay.refreshToggles(meta: meta)
            case "toggle-sfx":
                meta.sfxOn.toggle()
                SaveStore.save(meta)
                AudioManager.shared.setSFXOn(meta.sfxOn)
                pauseOverlay.refreshToggles(meta: meta)
            case "toggle-haptics":
                meta.hapticsOn.toggle()
                SaveStore.save(meta)
                Haptics.shared.enabled = meta.hapticsOn
                pauseOverlay.refreshToggles(meta: meta)
            default:
                break
            }
            return
        }
        if let touch = touches.first, world.state == .playing, !gameOver.isVisible,
           nodes(at: touch.location(in: self)).contains(where: { $0.name == "pauseButton" }) {
            pauseGame()
            return
        }
        if gameOver.isVisible {
            guard let touch = touches.first else { return }
            let tapped = nodes(at: touch.location(in: self))
            if tapped.contains(where: { $0.name == "labButton" }) {
                let lab = UpgradeLabScene(size: size)
                lab.scaleMode = .resizeFill
                view?.presentScene(lab, transition: .fade(withDuration: 0.3))
                return
            }
            if tapped.contains(where: { $0.name == "shareButton" }), let view {
                ShareCard.share(time: world.time, kills: world.kills,
                                level: world.player.level,
                                victory: world.state == .victory, from: view)
                return
            }
            if tapped.contains(where: { $0.name == "menuButton" }) {
                gameOver.hide()
                wasPlayRequested = false
                runIndex = 0
                meta = SaveStore.load()
                configureWorld()
                return
            }
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
