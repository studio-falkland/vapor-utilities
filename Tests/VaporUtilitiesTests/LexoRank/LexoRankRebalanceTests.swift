import Testing
import VaporUtilities

// MARK: - rebalanced

@Test("rebalanced spreads ranks evenly and keeps the order")
func rebalancedSpreadsRanks() throws {
    let ranks = try ["a", "a0", "a00"].map { LexoRank($0)! }.rebalanced()

    #expect(ranks.map(\.description) == ["9001", "i002", "r003"])
}

@Test("rebalanced depends only on the number of ranks")
func rebalancedIsIdempotent() throws {
    let ranks = try ["a", "b", "c", "d"].map { LexoRank($0)! }.rebalanced()

    #expect(try ranks.rebalanced() == ranks)
}

@Test("rebalanced leaves room between neighbours")
func rebalancedLeavesRoom() throws {
    var ranks = [LexoRank.middle]
    for _ in 0..<99 {
        ranks.append(ranks[ranks.count - 1].next())
    }

    let spread = try ranks.rebalanced()

    for (lower, upper) in zip(spread, spread.dropFirst()) {
        let between = try LexoRank.between(lower, upper)
        #expect(lower < between && between < upper)
    }
}

@Test("rebalanced rejects unordered input")
func rebalancedRejectsUnorderedInput() {
    let ranks = [LexoRank("b")!, LexoRank("a")!]

    #expect(throws: LexoRankError.invalidOrder(lower: ranks[0], upper: ranks[1])) {
        try ranks.rebalanced()
    }
}

@Test("rebalanced handles empty and single lists")
func rebalancedHandlesSmallLists() throws {
    #expect(try [LexoRank]().rebalanced() == [])
    #expect(try [LexoRank.middle].rebalanced() == [LexoRank("i001")!])
}
