import Vapor

extension Validator where T == String {
    /// Validates that a string is a lexorank.
    ///
    /// Accepts everything ``LexoRank/init(_:)`` accepts: base-36 digits with optional
    /// uppercase letters. Parsing folds case, so store the parsed rank rather than the
    /// raw string — uppercase sorts before lowercase and would corrupt the order.
    ///
    /// ```swift
    /// struct CardPatch: Content, Validatable {
    ///     var rank: String
    ///
    ///     static func validations(_ validations: inout Validations) {
    ///         validations.add("rank", as: String.self, is: .lexoRank)
    ///     }
    /// }
    /// ```
    public static var lexoRank: Validator<T> {
        .init { value in
            ValidatorResults.LexoRank(isValid: LexoRank(value) != nil)
        }
    }
}

extension ValidatorResults {
    /// `ValidatorResult` of a validator that validates whether a `String` is a lexorank.
    public struct LexoRank: Sendable {
        /// The input is a valid lexorank.
        public let isValid: Bool

        public init(isValid: Bool) {
            self.isValid = isValid
        }
    }
}

extension ValidatorResults.LexoRank: ValidatorResult {
    public var isFailure: Bool {
        !self.isValid
    }

    public var successDescription: String? {
        "is a valid lexorank"
    }

    public var failureDescription: String? {
        "is not a valid lexorank"
    }
}
