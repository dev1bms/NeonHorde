import SpriteKit
import NeonHordeCore

/// Loads the owner-generated art from the bundle (GOAL AMENDMENT v3) and
/// slices sprite sheets into animation frames. EVERY asset is optional —
/// missing pieces fall back to the procedural TextureBaker so the game is
/// always buildable regardless of how much of ART_PROMPTS.md has been
/// generated. Integration copies ArtDrop/* into App/Resources/Art/.
final class ArtLibrary {
    struct AnimatedSprite {
        let frames: [SKTexture]
        let fps: Double
    }

    // Hero
    private(set) var playerRun: AnimatedSprite?
    private(set) var playerIdle: AnimatedSprite?
    private(set) var playerAttack: AnimatedSprite?
    private(set) var playerDeath: AnimatedSprite?

    // Monsters: [walkA, walkB, attack] per kind
    private(set) var monsterFrames: [EnemyKind: [SKTexture]] = [:]
    private(set) var monsterShot: SKTexture?
    private(set) var bossFrames: [SKTexture]?

    // Environment
    private(set) var grounds: [SKTexture] = []      // per stage
    private(set) var props: [SKTexture] = []

    // UI
    private(set) var uiKit: SKTexture?
    private(set) var weaponIcons: [SKTexture] = []

    /// True when the hero sheets exist — the scene switches from geometric
    /// player rendering to character animation.
    var hasHero: Bool { playerRun != nil }

    init() {
        playerRun = slice("player_run", frames: 6, fps: 12)
        playerIdle = slice("player_idle", frames: 4, fps: 6)
        playerAttack = slice("player_attack", frames: 6, fps: 18)
        playerDeath = slice("player_death", frames: 6, fps: 10)

        let monsterFiles: [(EnemyKind, String)] = [
            (.dart, "monster_wolf"), (.brick, "monster_troll"),
            (.splitter, "monster_slime"), (.weaver, "monster_wraith"),
            (.spitter, "monster_shaman"),
        ]
        for (kind, name) in monsterFiles {
            if let sheet = slice(name, frames: 3, fps: 6) {
                monsterFrames[kind] = sheet.frames
            }
        }
        monsterShot = texture("monster_shot")
        if let boss = slice("boss_prime", frames: 3, fps: 4) {
            bossFrames = boss.frames
        }

        for i in 1...3 {
            if let g = texture("ground_stage\(i)") { grounds.append(g) }
        }
        if let sheet = texture("props_sheet") {
            // 8 props in a 4×2 grid.
            for row in 0..<2 {
                for col in 0..<4 {
                    props.append(SKTexture(rect: CGRect(x: CGFloat(col) / 4,
                                                        y: CGFloat(row) / 2,
                                                        width: 0.25, height: 0.5),
                                           in: sheet))
                }
            }
        }
        uiKit = texture("ui_kit")
        if let icons = texture("weapon_icons") {
            for row in 0..<2 {
                for col in 0..<4 {
                    weaponIcons.append(SKTexture(rect: CGRect(x: CGFloat(col) / 4,
                                                              y: 1 - CGFloat(row + 1) / 2,
                                                              width: 0.25, height: 0.5),
                                                 in: icons))
                }
            }
        }
    }

    // MARK: - Helpers

    private func image(_ name: String) -> UIImage? {
        for candidate in ["\(name)", "Art/\(name)"] {
            if let url = Bundle.main.url(forResource: candidate, withExtension: "png"),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return nil
    }

    private func texture(_ name: String) -> SKTexture? {
        image(name).map { SKTexture(image: $0) }
    }

    /// Slices a single-row sheet. Cell boundaries are DETECTED from fully
    /// transparent column gaps (the slicer tool guarantees padded cells), so
    /// sheets may carry any frame count — a 4-frame attack with intact sword
    /// arcs beats a 6-frame one with severed arcs. Falls back to an equal
    /// `expected`-way split when detection looks implausible.
    private func slice(_ name: String, frames expected: Int, fps: Double) -> AnimatedSprite? {
        guard let img = image(name) else { return nil }
        let sheet = SKTexture(image: img)
        var spans = alphaColumnSpans(of: img)
        #if DEBUG
        print("ARTLOG \(name): image=\(Int(img.size.width))x\(Int(img.size.height)) " +
              "scale=\(img.scale) detectedSpans=\(spans.count) expected=\(expected)")
        #endif
        if spans.count < 2 || spans.count > expected + 3 {
            spans = (0..<expected).map {
                (CGFloat($0) / CGFloat(expected), CGFloat($0 + 1) / CGFloat(expected))
            }
        }
        let result: [SKTexture] = spans.map { s in
            let frame = SKTexture(rect: CGRect(x: s.0, y: 0, width: s.1 - s.0, height: 1),
                                  in: sheet)
            frame.filteringMode = .linear
            return frame
        }
        return AnimatedSprite(frames: result, fps: fps)
    }

    /// Normalized (start, end) x-ranges of content columns, split on ≥4px
    /// fully-transparent gaps. Reads the alpha channel once via CoreGraphics.
    private func alphaColumnSpans(of img: UIImage) -> [(CGFloat, CGFloat)] {
        guard let cg = img.cgImage else { return [] }
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return [] }
        var alpha = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &alpha, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else {
            return []
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var columnHasContent = [Bool](repeating: false, count: w)
        for x in 0..<w {
            var count = 0
            var y = 0
            while y < h {
                if alpha[y * w + x] > 20 { count += 1 }
                y += 4   // sample every 4th row — plenty for gap detection
            }
            columnHasContent[x] = count > max(1, h / 200)
        }
        var spans: [(Int, Int)] = []
        var start: Int?
        var gap = 0
        for x in 0..<w {
            if columnHasContent[x] {
                if start == nil { start = x }
                gap = 0
            } else if start != nil {
                gap += 1
                if gap >= 4 {
                    spans.append((start!, x - gap + 1))
                    start = nil
                    gap = 0
                }
            }
        }
        if let s = start { spans.append((s, w)) }
        return spans
            .filter { $0.1 - $0.0 > w / 40 }
            .map { (CGFloat($0.0) / CGFloat(w), CGFloat($0.1) / CGFloat(w)) }
    }
}
