import Foundation
import Testing
import VaporUtilities

// MARK: - Parsing

@Test("Parses base-36 ranks")
func parsesRanks() {
    #expect(LexoRank("a05h")?.description == "a05h")
    #expect(LexoRank("0")?.description == "0")
    #expect(LexoRank("i000")?.description == "i000")
}

@Test("Folds uppercase letters to lowercase")
func foldsUppercase() {
    #expect(LexoRank("A05H")?.description == "a05h")
}

@Test("Rejects anything outside the alphabet")
func rejectsInvalidRanks() {
    #expect(LexoRank("") == nil)
    #expect(LexoRank("a b") == nil)
    #expect(LexoRank("a|1") == nil)
    #expect(LexoRank("a1-") == nil)
    #expect(LexoRank("ä") == nil)
}

// MARK: - Ordering

@Test("Ranks compare like their string form")
func comparesLikeStrings() {
    let pairs = [("0", "1"), ("9", "a"), ("a1", "a1i"), ("a1i", "a2"), ("z", "z0"), ("zz", "zz0")]

    for (lower, upper) in pairs {
        #expect(LexoRank(lower)! < LexoRank(upper)!)
        #expect(lower < upper)
    }
}

@Test("Equal ranks compare equal")
func equalRanksCompareEqual() {
    #expect(LexoRank("a05h") == LexoRank("a05h"))
    #expect(LexoRank("a05h") != LexoRank("a05i"))
}

// MARK: - Bounds

@Test("middle sits in the middle of the alphabet")
func middleIsCentered() {
    #expect(LexoRank.middle.description == "i000")
    #expect(LexoRank.minimum.description == "0")
    #expect(LexoRank.minimum < .middle)
}

// MARK: - next

@Test("next adds one unit")
func nextAddsOneUnit() {
    #expect(LexoRank("a5")!.next().description == "a6")
    #expect(LexoRank("i000")!.next().description == "i001")
    #expect(LexoRank("i00z")!.next().description == "i010")
    #expect(LexoRank("i0zz")!.next().description == "i100")
}

@Test("next appends the smallest digit when every digit is at the top")
func nextAtTopOfAlphabet() {
    #expect(LexoRank("z")!.next().description == "z0")
    #expect(LexoRank("zz")!.next().description == "zz0")
}

@Test("Repeated next calls stay ordered and short")
func repeatedNextStaysOrdered() {
    var rank = LexoRank.middle

    for _ in 0..<10_000 {
        let next = rank.next()
        #expect(rank < next)
        rank = next
    }

    #expect(rank.description.count <= 6)
}

// MARK: - previous

@Test("previous subtracts one unit")
func previousSubtractsOneUnit() throws {
    #expect(try LexoRank("a6")!.previous().description == "a5")
    #expect(try LexoRank("i001")!.previous().description == "i000")
    #expect(try LexoRank("i010")!.previous().description == "i00z")
    #expect(try LexoRank("i000")!.previous().description == "hzzz")
}

@Test("previous throws at the minimum rank")
func previousThrowsAtMinimum() {
    #expect(throws: LexoRankError.noRankAvailable(lower: nil, upper: .minimum)) {
        try LexoRank.minimum.previous()
    }
}

@Test("Repeated previous calls stay ordered")
func repeatedPreviousStaysOrdered() throws {
    var rank = LexoRank.middle

    for _ in 0..<10_000 {
        let previous = try rank.previous()
        #expect(previous < rank)
        rank = previous
    }
}

// MARK: - Codable

@Test("Encodes and decodes as a single JSON string")
func codableRoundTrip() throws {
    let rank = try #require(LexoRank("a05h"))
    let data = try JSONEncoder().encode(rank)

    #expect(String(decoding: data, as: UTF8.self) == "\"a05h\"")
    #expect(try JSONDecoder().decode(LexoRank.self, from: data) == rank)
}

@Test("Decoding rejects invalid ranks")
func decodingRejectsInvalidRanks() {
    let data = Data("\"a|b\"".utf8)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(LexoRank.self, from: data)
    }
}
