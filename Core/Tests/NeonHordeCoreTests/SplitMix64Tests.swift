import XCTest
@testable import NeonHordeCore

final class SplitMix64Tests: XCTestCase {
    func testDeterminismSameSeedSameSequence() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        for _ in 0..<1000 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testDifferentSeedsDiverge() {
        var a = SplitMix64(seed: 1)
        var b = SplitMix64(seed: 2)
        var same = 0
        for _ in 0..<100 where a.next() == b.next() { same += 1 }
        XCTAssertLessThan(same, 3)
    }

    func testUnitFloatBounds() {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<10_000 {
            let f = rng.unitFloat()
            XCTAssertGreaterThanOrEqual(f, 0)
            XCTAssertLessThan(f, 1)
        }
    }

    func testIntInRangeBounds() {
        var rng = SplitMix64(seed: 9)
        for _ in 0..<10_000 {
            let v = rng.int(in: -3...5)
            XCTAssertTrue((-3...5).contains(v))
        }
    }
}
