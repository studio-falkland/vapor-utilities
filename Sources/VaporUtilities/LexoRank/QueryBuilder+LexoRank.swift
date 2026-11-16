import FluentKit

extension QueryBuilder where Model: FluentKit.Model {
    /// Returns the highest rank matching the query's filters, or `nil` when nothing
    /// matches.
    ///
    /// ```swift
    /// let last = try await Card.query(on: db)
    ///     .filter(\.$list.$id == listID)
    ///     .lastLexoRank(\.$rank)
    /// ```
    ///
    /// - Parameter field: A key path to the rank field.
    public func lastLexoRank(
        _ field: KeyPath<Model, FieldProperty<Model, LexoRank>>
    ) async throws -> LexoRank? {
        try await self.copy()
            .sort(field, .descending)
            .first()?[keyPath: field].value
    }

    /// Returns a rank that sorts after every row matching the query's filters.
    ///
    /// Returns ``LexoRank/middle`` when the query matches nothing, so the first row of
    /// a new list starts in the middle of the alphabet.
    ///
    /// ```swift
    /// let card = Card()
    /// card.rank = try await Card.query(on: db)
    ///     .filter(\.$list.$id == listID)
    ///     .nextLexoRank(\.$rank)
    /// ```
    ///
    /// > Important: The value is computed from a read, so two concurrent appends can
    /// > produce the same rank. Add a unique index on the rank column and retry, or
    /// > serialise the writes.
    ///
    /// - Parameter field: A key path to the rank field.
    public func nextLexoRank(
        _ field: KeyPath<Model, FieldProperty<Model, LexoRank>>
    ) async throws -> LexoRank {
        guard let last = try await self.lastLexoRank(field) else { return .middle }
        return last.next()
    }

    /// Rewrites the rank of every row matching the query, spreading the values evenly.
    ///
    /// Use this to recover from ``LexoRankError/noRankAvailable(lower:upper:)``. Rows
    /// keep their current order and only rows whose rank changed are saved.
    ///
    /// ```swift
    /// try await db.transaction { db in
    ///     try await Card.query(on: db)
    ///         .filter(\.$list.$id == listID)
    ///         .rebalanceLexoRanks(\.$rank)
    /// }
    /// ```
    ///
    /// > Important: Ranks are only meaningful inside one ordered set. Rebalance a
    /// > complete sibling set — every row that shares the same parent — never a page
    /// > or a filtered subset of it.
    ///
    /// - Parameter field: A key path to the rank field.
    /// - Returns: The matching models, in rank order, with their new ranks applied.
    /// - Throws: ``LexoRankError/missingRank`` when a row was loaded without its rank
    ///   column.
    @discardableResult
    public func rebalanceLexoRanks(
        _ field: KeyPath<Model, FieldProperty<Model, LexoRank>>
    ) async throws -> [Model] {
        let models = try await self.copy().sort(field).all()

        // Collect the current ranks in order and replace them with an even spread.
        let ranks = try models.map { model -> LexoRank in
            guard let rank = model[keyPath: field].value else {
                throw LexoRankError.missingRank
            }
            return rank
        }
        let rebalanced = try ranks.rebalanced()

        // Save only the rows that actually moved, so a repeated rebalance is cheap.
        for (model, rank) in zip(models, rebalanced) where model[keyPath: field].value != rank {
            model[keyPath: field].value = rank
            try await model.save(on: self.database)
        }
        return models
    }
}
