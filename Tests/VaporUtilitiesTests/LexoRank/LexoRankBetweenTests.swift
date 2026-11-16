import Testing
import VaporUtilities

// MARK: - between

@Test("between returns the shortest rank inside the gap")
func betweenProducesExpectedRanks() throws {
    let cases: [(lower: String?, upper: String?, expected: String)] = [
        (nil, nil, "i000"),
        (nil, "i000", "hzzz"),
        (nil, "1", "0"),
        ("a", "b", "ai"),
        ("a1", "a2", "a1i"),
        ("a", "a0b", "a0a"),
        ("a", "a1", "a0"),
        ("az", "b", "azi"),
        ("z", "zz", "zh"),
        ("zz", "zz1", "zz0"),
        ("0", "000", "00"),
    ]

    for testCase in cases {
        let lower = testCase.lower.map { LexoRank($0)! }
        let upper = testCase.upper.map { LexoRank($0)! }
        let result = try LexoRank.between(lower, upper)
        let label = "between(\(testCase.lower ?? "nil"), \(testCase.upper ?? "nil"))"

        #expect(result.description == testCase.expected, "\(label) returned '\(result)'")
    }
}

@Test("between rejects bounds that are out of order")
func betweenRejectsReversedBounds() {
    let lower = LexoRank("b")!
    let upper = LexoRank("a")!

    #expect(throws: LexoRankError.invalidOrder(lower: lower, upper: upper)) {
        try LexoRank.between(lower, upper)
    }
    #expect(throws: LexoRankError.invalidOrder(lower: lower, upper: lower)) {
        try LexoRank.between(lower, lower)
    }
}

@Test("between throws when the bounds are adjacent")
func betweenThrowsWhenAdjacent() {
    let lower = LexoRank("a")!
    let upper = LexoRank("a0")!

    #expect(throws: LexoRankError.noRankAvailable(lower: lower, upper: upper)) {
        try LexoRank.between(lower, upper)
    }
}

@Test("Nothing sorts below the minimum")
func nothingSortsBelowMinimum() {
    #expect(throws: LexoRankError.noRankAvailable(lower: nil, upper: .minimum)) {
        try LexoRank.between(nil, .minimum)
    }
}

// MARK: - Insertion

@Test("Insertion stays ordered and rebalances when a gap runs out")
func insertionStaysOrdered() throws {
    var ranks = [LexoRank.middle]
    var generator = SeededGenerator(seed: 0x5EED)
    var rebalances = 0

    for _ in 0..<2_000 {
        let slot = Int.random(in: 0...ranks.count, using: &generator)
        let lower = slot > 0 ? ranks[slot - 1] : nil
        let upper = slot < ranks.count ? ranks[slot] : nil

        do {
            ranks.insert(try LexoRank.between(lower, upper), at: slot)
        } catch LexoRankError.noRankAvailable {
            // A gap ran out: spread the whole list, then insert again.
            ranks = try ranks.rebalanced()
            rebalances += 1

            let newLower = slot > 0 ? ranks[slot - 1] : nil
            let newUpper = slot < ranks.count ? ranks[slot] : nil
            ranks.insert(try LexoRank.between(newLower, newUpper), at: slot)
        }

        #expect(zip(ranks, ranks.dropFirst()).allSatisfy { $0 < $1 })
    }

    #expect(rebalances > 0)
    #expect(Set(ranks).count == ranks.count)
}

/// A deterministic generator so a failure reproduces on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
