import Foundation

struct Block: Codable, Hashable {
    let start: Int64
    let end: Int64
    var key: String { "\(start):\(end)" }
}

// Union only occupied intervals. No source identifiers or descriptive fields.
func mergeBlocks(_ input: [Block]) -> [Block] {
    let sorted = input.filter { $0.end > $0.start }.sorted {
        $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
    }
    var result: [Block] = []
    for block in sorted {
        if let last = result.last, block.start <= last.end {
            result[result.count - 1] = Block(start: last.start, end: max(last.end, block.end))
        } else { result.append(block) }
    }
    return result
}

struct Diff {
    var retained: [Int] = []
    var stale: [Int] = []
    var create: [Block] = []
}
func reconcile(_ wanted: [Block], _ existing: [Block]) -> Diff {
    let keys = Set(wanted.map(\.key))
    var seen = Set<String>()
    var result = Diff()
    for (index, block) in existing.enumerated() {
        if keys.contains(block.key) && seen.insert(block.key).inserted { result.retained.append(index) }
        else { result.stale.append(index) }
    }
    result.create = wanted.filter { !seen.contains($0.key) }
    return result
}

func plannerTests() {
    assert(mergeBlocks([]).isEmpty)
    assert(mergeBlocks([Block(start: 1, end: 2), Block(start: 2, end: 3)]) == [Block(start: 1, end: 3)])
    assert(mergeBlocks([Block(start: 5, end: 8), Block(start: 1, end: 7), Block(start: 2, end: 3)]) == [Block(start: 1, end: 8)])
    assert(mergeBlocks([Block(start: 1, end: 2), Block(start: 3, end: 4)]).count == 2)
    assert(mergeBlocks([Block(start: 1, end: 1), Block(start: 3, end: 2)]).isEmpty)
    assert(mergeBlocks([Block(start: 1, end: 2), Block(start: 1, end: 2)]).count == 1)
    // Absolute timestamps preserve elapsed intervals across timezone/DST boundaries.
    assert(mergeBlocks([Block(start: 1792890000, end: 1792897200)]).first?.end == 1792897200)
    let a = Block(start: 10, end: 20), b = Block(start: 30, end: 40)
    let unchanged = reconcile([a, b], [a, b])
    assert(unchanged.create.isEmpty && unchanged.stale.isEmpty)
    let moved = reconcile([b], [a])
    assert(moved.create == [b] && moved.stale == [0])
    assert(reconcile([], [a]).stale == [0])
    let duplicate = reconcile([a], [a, a])
    assert(duplicate.create.isEmpty && duplicate.retained == [0] && duplicate.stale == [1])
    let split = reconcile([a, b], [Block(start: 10, end: 40)])
    assert(split.create == [a, b] && split.stale == [0])
}
