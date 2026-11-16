/// Errors thrown when a rank cannot be produced.
public enum LexoRankError: Error, Equatable, Sendable {
    /// The lower bound was not strictly less than the upper bound.
    case invalidOrder(lower: LexoRank, upper: LexoRank)

    /// No rank exists in the gap: the bounds are adjacent.
    ///
    /// Every pair of bounds has a rank between them except when the lower bound is a
    /// prefix of the upper one and the rest of the upper bound is zeros — for example
    /// `"a"` and `"a0"`, where `"a0"` is the immediate successor of `"a"`.
    ///
    /// Rebalance the list with `rebalanced()` to restore room.
    case noRankAvailable(lower: LexoRank?, upper: LexoRank?)

    /// A model was loaded without its rank column, so it has no rank to rebalance.
    case missingRank
}

extension LexoRankError: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .invalidOrder(lower, upper):
            "LexoRankError: lower bound '\(lower)' is not less than upper bound '\(upper)'"
        case let .noRankAvailable(lower, upper):
            "LexoRankError: no rank available between '\(lower.map(\.description) ?? "start")' "
                + "and '\(upper.map(\.description) ?? "end")'; rebalance the list"
        case .missingRank:
            "LexoRankError: a row was loaded without its rank column"
        }
    }
}
