import XCTest
@testable import NeonHordeCore

final class SpatialHashTests: XCTestCase {
    /// Hash queries must exactly match a brute-force radius scan.
    func testQueriesMatchBruteForce() {
        var rng = SplitMix64(seed: 1234)
        var hash = SpatialHash(cellSize: 64, capacity: 500)
        var xs: [Float] = [], ys: [Float] = []
        for i in 0..<500 {
            let x = rng.float(in: -1000...1000)
            let y = rng.float(in: -1000...1000)
            xs.append(x)
            ys.append(y)
            hash.insert(id: Int32(i), x: x, y: y)
        }
        for _ in 0..<200 {
            let qx = rng.float(in: -1100...1100)
            let qy = rng.float(in: -1100...1100)
            let r = rng.float(in: 1...300)
            var expected = Set<Int32>()
            for i in 0..<500 {
                let dx = xs[i] - qx, dy = ys[i] - qy
                if dx * dx + dy * dy <= r * r { expected.insert(Int32(i)) }
            }
            var got = Set<Int32>()
            hash.forEachNeighbor(x: qx, y: qy, radius: r) { id, _, _ in got.insert(id) }
            XCTAssertEqual(got, expected, "radius query mismatch at (\(qx),\(qy)) r=\(r)")
        }
    }

    func testNegativeCoordinatesAndCellEdges() {
        var hash = SpatialHash(cellSize: 64, capacity: 16)
        // Points exactly on cell boundaries and deep in negative space.
        let pts: [(Float, Float)] = [(0, 0), (-64, -64), (64, 64), (-0.001, -0.001),
                                     (-1000, 500), (63.999, -64.0)]
        for (i, p) in pts.enumerated() {
            hash.insert(id: Int32(i), x: p.0, y: p.1)
        }
        var got = Set<Int32>()
        hash.forEachNeighbor(x: 0, y: 0, radius: 2000) { id, _, _ in got.insert(id) }
        XCTAssertEqual(got.count, pts.count)
        // Tight query around a boundary point only finds that point.
        got.removeAll()
        hash.forEachNeighbor(x: -64, y: -64, radius: 0.5) { id, _, _ in got.insert(id) }
        XCTAssertEqual(got, [1])
    }

    func testClearEmptiesEverything() {
        var hash = SpatialHash(cellSize: 32, capacity: 8)
        hash.insert(id: 7, x: 5, y: 5)
        hash.clear()
        var visits = 0
        hash.forEachNeighbor(x: 5, y: 5, radius: 100) { _, _, _ in visits += 1 }
        XCTAssertEqual(visits, 0)
        XCTAssertEqual(hash.count, 0)
        // Reuse after clear works.
        hash.insert(id: 9, x: 1, y: 1)
        hash.forEachNeighbor(x: 0, y: 0, radius: 10) { id, _, _ in
            XCTAssertEqual(id, 9)
            visits += 1
        }
        XCTAssertEqual(visits, 1)
    }
}
