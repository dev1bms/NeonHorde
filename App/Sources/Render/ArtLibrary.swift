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

    private func texture(_ name: String) -> SKTexture? {
        // Art files are bundled as loose resources (Art/<name>.png).
        for candidate in ["\(name)", "Art/\(name)"] {
            if let url = Bundle.main.url(forResource: candidate, withExtension: "png") {
                if let image = UIImage(contentsOfFile: url.path) {
                    return SKTexture(image: image)
                }
            }
        }
        return nil
    }

    /// Slices an N-frame single-row sheet using normalized rects (robust to
    /// whatever pixel size the image model actually produced).
    private func slice(_ name: String, frames: Int, fps: Double) -> AnimatedSprite? {
        guard let sheet = texture(name) else { return nil }
        var result: [SKTexture] = []
        for i in 0..<frames {
            let rect = CGRect(x: CGFloat(i) / CGFloat(frames), y: 0,
                              width: 1 / CGFloat(frames), height: 1)
            let frame = SKTexture(rect: rect, in: sheet)
            frame.filteringMode = .linear
            result.append(frame)
        }
        return AnimatedSprite(frames: result, fps: fps)
    }
}
