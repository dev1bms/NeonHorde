import UIKit
import NeonHordeCore

/// Run-result share card rendered with UIGraphicsImageRenderer for exact
/// pixel control (GOAL Phase 8). Shared via UIActivityViewController.
enum ShareCard {
    static func render(time: Float, kills: Int, level: Int, victory: Bool) -> UIImage {
        let size = CGSize(width: 1080, height: 1350)   // 4:5 social format
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Background gradient + grid.
            let colors = [UIColor(red: 0.07, green: 0.05, blue: 0.17, alpha: 1).cgColor,
                          Palette.uiBackground.cgColor]
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(grad, start: .zero,
                                  end: CGPoint(x: 0, y: size.height), options: [])
            cg.setStrokeColor(Palette.player.withAlphaComponent(0.07).cgColor)
            cg.setLineWidth(2)
            var offset: CGFloat = 0
            while offset < size.width {
                cg.stroke(CGRect(x: offset, y: 0, width: 0.5, height: size.height))
                offset += 108
            }
            offset = 0
            while offset < size.height {
                cg.stroke(CGRect(x: 0, y: offset, width: size.width, height: 0.5))
                offset += 108
            }

            func draw(_ text: String, size fontSize: CGFloat, color: UIColor,
                      y: CGFloat, bold: Bool = true) {
                let font = UIFont(name: bold ? "Menlo-Bold" : "Menlo", size: fontSize)
                    ?? .monospacedSystemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let str = NSAttributedString(string: text, attributes: attrs)
                let bounds = str.size()
                str.draw(at: CGPoint(x: (1080 - bounds.width) / 2, y: y))
            }

            draw("NEON", size: 120, color: Palette.player, y: 150)
            draw("HORDE", size: 120, color: Palette.enemyLow, y: 280)

            draw(victory ? "HORDE BROKEN" : "RUN OVER",
                 size: 64, color: victory ? Palette.gem : Palette.enemyLow, y: 520)

            let t = Int(time)
            draw(String(format: "%d:%02d", t / 60, t % 60), size: 160, color: Palette.ui, y: 650)
            draw("SURVIVED", size: 32, color: Palette.ui.withAlphaComponent(0.5), y: 830)

            draw("✕ \(kills) KILLS      LV \(level)", size: 44,
                 color: Palette.enemyHigh, y: 950)

            draw(victory ? "PRIME HAS FALLEN." : "the horde is undefeated.",
                 size: 30, color: Palette.ui.withAlphaComponent(0.7), y: 1120, bold: false)
            draw("— NEON HORDE for iPhone —", size: 26,
                 color: Palette.player.withAlphaComponent(0.8), y: 1240, bold: false)
        }
    }

    /// Presents the system share sheet with the card + a taunt line.
    static func share(time: Float, kills: Int, level: Int, victory: Bool,
                      from view: UIView) {
        let image = render(time: time, kills: kills, level: level, victory: victory)
        let t = Int(time)
        let text = victory
            ? "I broke the horde in NEON HORDE 🏆"
            : String(format: "Survived %d:%02d against the NEON HORDE — beat that.", t / 60, t % 60)
        let activity = UIActivityViewController(activityItems: [image, text],
                                                applicationActivities: nil)
        view.window?.rootViewController?.present(activity, animated: true)
    }
}
