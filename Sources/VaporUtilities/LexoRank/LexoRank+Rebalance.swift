extension Array where Element == LexoRank {
    /// Replaces these ranks with evenly spaced ones, keeping their order.
    ///
    /// Use this to recover from ``LexoRankError/noRankAvailable(lower:upper:)``: fetch
    /// the rows in rank order, compute replacements, and save them. The result depends
    /// only on the number of elements, so running it twice is a no-op.
    ///
    /// ```swift
    /// let cards = try await Card.query(on: db)
    ///     .filter(\.$list.$id == listID)
    ///     .sort(\.$rank)
    ///     .all()
    /// let ranks = try cards.map(\.rank).rebalanced()
    /// for (card, rank) in zip(cards, ranks) {
    ///     card.rank = rank
    ///     try await card.save(on: db)
    /// }
    /// ```
    ///
    /// > Important: Ranks are only meaningful inside one ordered set. Rebalance a
    /// > complete sibling set — every row that shares the same parent — never a page
    /// > or a filtered subset of it.
    ///
    /// - Throws: ``LexoRankError/invalidOrder(lower:upper:)`` when the receiver is not
    ///   strictly increasing.
    public func rebalanced() throws -> [LexoRank] {
        // Reject unordered input up front: the replacement values would silently
        // scramble the list otherwise.
        for index in indices.dropFirst() where self[index - 1] >= self[index] {
            throw LexoRankError.invalidOrder(lower: self[index - 1], upper: self[index])
        }

        guard !isEmpty else { return [] }

        // Pick a width that leaves at least 36 slots between neighbours, so the next
        // few insertions in any gap succeed without another rebalance.
        var width = 4
        var total = UInt64(LexoRank.base) * UInt64(LexoRank.base)
            * UInt64(LexoRank.base) * UInt64(LexoRank.base)
        let needed = UInt64(LexoRank.base) * (UInt64(count) + 1)
        while width < 12 && total < needed {
            width += 1
            total *= UInt64(LexoRank.base)
        }

        // Spread the values across the space, one step apart from each other. The
        // width above keeps the step at 36 or more, so the ranks never collide.
        var step = total / (UInt64(count) + 1)

        // A step that is a multiple of 36 leaves the low digits of every rank at zero.
        // Nudge it by one so the ranks carry information, as long as the last value
        // still fits inside the space.
        if step % UInt64(LexoRank.base) == 0, UInt64(count) * (step + 1) < total {
            step += 1
        }

        return (1...count).map { position in
            LexoRank(digits: Self.digits(of: UInt64(position) * step, width: width))
        }
    }

    /// Expands a value into exactly `width` base-36 digits, most significant first.
    private static func digits(of value: UInt64, width: Int) -> [UInt8] {
        var value = value
        var digits = [UInt8](repeating: 0, count: width)

        for index in stride(from: width - 1, through: 0, by: -1) {
            digits[index] = UInt8(value % UInt64(LexoRank.base))
            value /= UInt64(LexoRank.base)
        }
        return digits
    }
}
