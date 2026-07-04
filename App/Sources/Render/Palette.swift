import UIKit

/// Single source of truth for the game's visual identity (GOAL §4 Art direction).
enum Palette {
    static let uiBackground = UIColor(red: 0.039, green: 0.039, blue: 0.071, alpha: 1) // #0A0A12
    static let player = UIColor(red: 0.220, green: 0.941, blue: 1.000, alpha: 1)       // #38F0FF
    static let enemyLow = UIColor(red: 1.000, green: 0.239, blue: 0.682, alpha: 1)     // #FF3DAE
    static let enemyHigh = UIColor(red: 1.000, green: 0.478, blue: 0.102, alpha: 1)    // #FF7A1A
    static let gem = UIColor(red: 0.714, green: 1.000, blue: 0.180, alpha: 1)          // #B6FF2E
    static let ui = UIColor.white

    /// Threat ramp: t in 0...1 → magenta→orange.
    static func enemy(threat t: CGFloat) -> UIColor {
        var r0: CGFloat = 0, g0: CGFloat = 0, b0: CGFloat = 0, a0: CGFloat = 0
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        enemyLow.getRed(&r0, green: &g0, blue: &b0, alpha: &a0)
        enemyHigh.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        let c = max(0, min(1, t))
        return UIColor(red: r0 + (r1 - r0) * c, green: g0 + (g1 - g0) * c, blue: b0 + (b1 - b0) * c, alpha: 1)
    }
}
