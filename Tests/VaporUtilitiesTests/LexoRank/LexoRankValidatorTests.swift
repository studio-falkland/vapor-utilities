import Testing
import Vapor
import VaporUtilities

// MARK: - Validator

@Test("Accepts valid lexorank strings")
func validatorAcceptsValidRanks() throws {
    var validations = Validations()
    validations.add("rank", as: String.self, is: .lexoRank)

    for rank in ["0", "a05h", "i000", "zzzz", "A05H"] {
        let result = try validations.validate(json: #"{"rank": "\#(rank)"}"#)
        #expect(result.error == nil, "'\(rank)' should be valid")
    }
}

@Test("Rejects strings that are not lexoranks")
func validatorRejectsInvalidRanks() throws {
    var validations = Validations()
    validations.add("rank", as: String.self, is: .lexoRank)

    for rank in ["", "a b", "a|1", "a1-", "ä", "a05h!"] {
        let result = try validations.validate(json: #"{"rank": "\#(rank)"}"#)
        #expect(result.error != nil, "'\(rank)' should be invalid")
    }
}

@Test("Reports a useful failure description")
func validatorReportsFailureDescription() throws {
    var validations = Validations()
    validations.add("rank", as: String.self, is: .lexoRank)

    let result = try validations.validate(json: #"{"rank": "a|b"}"#)

    #expect(result.error?.description == "rank is not a valid lexorank")
}

@Test("Requires the key by default")
func validatorRequiresKey() throws {
    var validations = Validations()
    validations.add("rank", as: String.self, is: .lexoRank)

    let result = try validations.validate(json: "{}")

    #expect(result.error?.description == "rank is required")
}

@Test("Composes with other validators")
func validatorComposes() throws {
    var validations = Validations()
    validations.add("rank", as: String.self, is: .lexoRank && !.empty)

    #expect(try validations.validate(json: #"{"rank": "a05h"}"#).error == nil)
    #expect(try validations.validate(json: #"{"rank": ""}"#).error != nil)
}
