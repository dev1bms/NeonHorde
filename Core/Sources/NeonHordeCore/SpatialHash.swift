/// Allocation-free uniform-grid spatial hash (GOAL §5).
/// Rebuilt every tick: `clear()` + `insert(...)` for each entity, then
/// neighborhood queries via `forEachNeighbor`. Buckets are chained through a
/// preallocated `nextSlot` array — no per-tick heap allocation, deterministic
/// iteration order (insertion order within a bucket, newest first).
public struct SpatialHash {
    public let cellSize: Float
    private let bucketMask: Int32
    private var bucketHead: [Int32]     // bucket → first slot index, -1 = empty
    private var nextSlot: [Int32]       // slot → next slot in same bucket
    private var slotX: [Float]
    private var slotY: [Float]
    private var slotID: [Int32]
    private var slotCount: Int

    public var count: Int { slotCount }
    public var capacity: Int { slotID.count }

    public init(cellSize: Float, capacity: Int, bucketCount: Int = 2048) {
        precondition(bucketCount > 0 && (bucketCount & (bucketCount - 1)) == 0,
                     "bucketCount must be a power of two")
        self.cellSize = cellSize
        self.bucketMask = Int32(bucketCount - 1)
        self.bucketHead = [Int32](repeating: -1, count: bucketCount)
        self.nextSlot = [Int32](repeating: -1, count: capacity)
        self.slotX = [Float](repeating: 0, count: capacity)
        self.slotY = [Float](repeating: 0, count: capacity)
        self.slotID = [Int32](repeating: 0, count: capacity)
        self.slotCount = 0
    }

    @inlinable func cellCoord(_ v: Float) -> Int32 {
        Int32((v / cellSize).rounded(.down))
    }

    @usableFromInline func bucketIndex(cx: Int32, cy: Int32) -> Int32 {
        // Deterministic integer hash of the cell coordinate pair.
        let h = (cx &* 92837111) ^ (cy &* 689287499)
        return h & bucketMask
    }

    public mutating func clear() {
        for i in bucketHead.indices { bucketHead[i] = -1 }
        slotCount = 0
    }

    /// Inserts an entity. Silently ignores inserts beyond capacity — pools cap
    /// entity counts upstream, so hitting this means a pool cap bug.
    public mutating func insert(id: Int32, x: Float, y: Float) {
        guard slotCount < slotID.count else {
            assertionFailure("SpatialHash capacity exceeded — pool caps must bound inserts")
            return
        }
        let slot = Int32(slotCount)
        slotCount += 1
        slotX[Int(slot)] = x
        slotY[Int(slot)] = y
        slotID[Int(slot)] = id
        let b = Int(bucketIndex(cx: cellCoord(x), cy: cellCoord(y)))
        nextSlot[Int(slot)] = bucketHead[b]
        bucketHead[b] = slot
    }

    /// Visits every entity whose position lies within `radius` of (x, y).
    /// Body receives (id, entityX, entityY).
    public func forEachNeighbor(x: Float, y: Float, radius: Float,
                                _ body: (Int32, Float, Float) -> Void) {
        let r2 = radius * radius
        let minCX = cellCoord(x - radius), maxCX = cellCoord(x + radius)
        let minCY = cellCoord(y - radius), maxCY = cellCoord(y + radius)
        var cy = minCY
        while cy <= maxCY {
            var cx = minCX
            while cx <= maxCX {
                var slot = bucketHead[Int(bucketIndex(cx: cx, cy: cy))]
                while slot >= 0 {
                    let i = Int(slot)
                    let ex = slotX[i], ey = slotY[i]
                    // Bucket collisions can chain entities from other cells;
                    // verify both cell membership and true distance.
                    if cellCoord(ex) == cx, cellCoord(ey) == cy {
                        let dx = ex - x, dy = ey - y
                        if dx * dx + dy * dy <= r2 {
                            body(slotID[i], ex, ey)
                        }
                    }
                    slot = nextSlot[i]
                }
                cx += 1
            }
            cy += 1
        }
    }
}
