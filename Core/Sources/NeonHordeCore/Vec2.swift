/// Minimal 2D float vector. Core avoids simd/Foundation to stay portable and
/// deterministic across the iOS app and native macOS test runs.
public struct Vec2: Equatable {
    public var x: Float
    public var y: Float

    public static let zero = Vec2(0, 0)

    @inlinable public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    @inlinable public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    @inlinable public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    @inlinable public static func * (a: Vec2, s: Float) -> Vec2 { Vec2(a.x * s, a.y * s) }
    @inlinable public static func += (a: inout Vec2, b: Vec2) { a.x += b.x; a.y += b.y }
    @inlinable public static func -= (a: inout Vec2, b: Vec2) { a.x -= b.x; a.y -= b.y }

    @inlinable public var lengthSquared: Float { x * x + y * y }
    @inlinable public var length: Float { lengthSquared.squareRoot() }

    /// Zero-safe normalization.
    @inlinable public var normalized: Vec2 {
        let l = length
        return l > 1e-6 ? Vec2(x / l, y / l) : .zero
    }

    @inlinable public func distanceSquared(to o: Vec2) -> Float {
        let dx = x - o.x, dy = y - o.y
        return dx * dx + dy * dy
    }

    /// Clamp magnitude to maxLength.
    @inlinable public func clamped(to maxLength: Float) -> Vec2 {
        let l2 = lengthSquared
        guard l2 > maxLength * maxLength, l2 > 0 else { return self }
        let s = maxLength / l2.squareRoot()
        return Vec2(x * s, y * s)
    }
}
