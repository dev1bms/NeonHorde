import SpriteKit
import NeonHordeCore

/// Pooled floating damage numbers, composed from the pre-baked digit atlas —
/// never SKLabelNode (GOAL §4 Juice: batching discipline).
final class DamageNumberRig {
    private struct Entry {
        var digits: [SKSpriteNode]
        var used = 0
        var age: CGFloat = 0
        var active = false
        var origin = CGPoint.zero
    }

    private var entries: [Entry] = []
    private var cursor = 0
    private let ttl: CGFloat = 0.6
    private let digitTextures: [SKTexture]

    init(parent: SKNode, baker: TextureBaker) {
        digitTextures = baker.digits
        for _ in 0..<Balance.damageNumberCap {
            var digits: [SKSpriteNode] = []
            for _ in 0..<4 {   // supports up to 9999
                let d = SKSpriteNode(texture: digitTextures[0])
                d.zPosition = ZBand.effects + 1
                d.isHidden = true
                d.blendMode = .add
                parent.addChild(d)
                digits.append(d)
            }
            entries.append(Entry(digits: digits))
        }
    }

    func spawn(amount: Int, at pos: CGPoint) {
        let idx = cursor
        cursor = (cursor + 1) % entries.count
        // Recycle-in-place even if still animating (oldest wins).
        for d in entries[idx].digits { d.isHidden = true }
        let text = String(min(amount, 9999))
        entries[idx].used = text.count
        entries[idx].age = 0
        entries[idx].active = true
        entries[idx].origin = pos
        let width = CGFloat(text.count) * 12
        for (i, ch) in text.enumerated() {
            let digit = entries[idx].digits[i]
            digit.texture = digitTextures[Int(String(ch)) ?? 0]
            digit.size = digit.texture!.size()
            digit.position = CGPoint(x: pos.x - width / 2 + CGFloat(i) * 12 + 6, y: pos.y)
            digit.isHidden = false
            digit.alpha = 1
        }
    }

    func update(dt: CGFloat) {
        for i in entries.indices where entries[i].active {
            entries[i].age += dt
            let t = entries[i].age / ttl
            if t >= 1 {
                entries[i].active = false
                for d in entries[i].digits { d.isHidden = true }
                continue
            }
            let rise = 26 * t
            let alpha = 1 - t * t
            for k in 0..<entries[i].used {
                let d = entries[i].digits[k]
                d.position.y = entries[i].origin.y + rise
                d.alpha = alpha
            }
        }
    }
}
