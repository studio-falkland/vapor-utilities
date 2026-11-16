import Foundation
import Testing
@preconcurrency import FluentKit
@preconcurrency import XCTFluent
@preconcurrency import VaporUtilities

// MARK: - Test Model

final class Card: Model, @unchecked Sendable {
    static let schema = "cards"
    static let space: String? = nil
    static let alias: String? = nil

    typealias IDValue = UUID

    @ID(key: .id)
    var id: UUID?

    @Field(key: "rank")
    var rank: LexoRank

    required init() {}
}

private func makeCard(_ rank: String) -> Card {
    let card = Card()
    card.id = UUID()
    card.rank = LexoRank(rank)!
    return card
}

// MARK: - lastLexoRank

@Test("lastLexoRank sorts by rank descending")
func lastLexoRankSortsDescending() async throws {
    let card = makeCard("b")

    let db = CallbackTestDatabase { query in
        guard case let .sort(field, direction)? = query.sorts.first, case .descending = direction else {
            Issue.record("Expected a descending sort")
            return []
        }

        // The sort is emitted against the model's schema, so the field arrives as an
        // extended path rather than a bare one.
        let path: [FieldKey]
        switch field {
        case let .path(fieldPath, _):
            path = fieldPath
        case let .extendedPath(fieldPath, _, _):
            path = fieldPath
        default:
            Issue.record("Expected a sort on a column path")
            return []
        }

        #expect(path.map(\.description) == ["rank"])
        return [TestOutput(card)]
    }

    let rank = try await Card.query(on: db.db).lastLexoRank(\.$rank)

    #expect(rank == LexoRank("b"))
}

@Test("lastLexoRank returns nil for an empty result")
func lastLexoRankReturnsNilWhenEmpty() async throws {
    let db = ArrayTestDatabase()
    db.append([])

    let rank = try await Card.query(on: db.db).lastLexoRank(\.$rank)

    #expect(rank == nil)
}

// MARK: - nextLexoRank

@Test("nextLexoRank starts a new list in the middle")
func nextLexoRankStartsInTheMiddle() async throws {
    let db = ArrayTestDatabase()
    db.append([])

    let rank = try await Card.query(on: db.db).nextLexoRank(\.$rank)

    #expect(rank == .middle)
}

@Test("nextLexoRank appends after the last rank")
func nextLexoRankAppends() async throws {
    let db = ArrayTestDatabase()
    db.append([makeCard("a5")])

    let rank = try await Card.query(on: db.db).nextLexoRank(\.$rank)

    #expect(rank == LexoRank("a6"))
}

// MARK: - rebalanceLexoRanks

@Test("rebalanceLexoRanks spreads the ranks and saves the rows")
func rebalanceLexoRanksSpreadsRanks() async throws {
    let db = ArrayTestDatabase()
    let cards = ["a", "a0", "a00"].map(makeCard)
    db.append(cards)

    // One empty result set per row update.
    for _ in cards {
        db.append([any DatabaseOutput]())
    }

    let rebalanced = try await Card.query(on: db.db).rebalanceLexoRanks(\.$rank)

    #expect(rebalanced.map(\.rank.description) == ["9001", "i002", "r003"])
}

@Test("rebalanceLexoRanks skips rows that already hold the target rank")
func rebalanceLexoRanksSkipsUnchangedRows() async throws {
    let db = ArrayTestDatabase()
    db.append(["9001", "i002", "r003"].map(makeCard))

    // No result sets are appended for updates, so any save would fail the test.
    let rebalanced = try await Card.query(on: db.db).rebalanceLexoRanks(\.$rank)

    #expect(rebalanced.map(\.rank.description) == ["9001", "i002", "r003"])
}

// MARK: - Field integration

@Test("The rank field encodes as a string")
func rankFieldEncodesAsString() throws {
    let data = try JSONEncoder().encode(makeCard("a05h"))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(json["rank"] as? String == "a05h")
}
