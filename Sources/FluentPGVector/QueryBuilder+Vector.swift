import FluentKit
import FluentSQL
import SQLKit

// MARK: - SQL expression for vector bindings

/// A SQL expression that serializes a vector array as a bind parameter
/// with a PostgreSQL `::vector` cast.
struct SQLVectorBinding: SQLExpression {
    let values: [Double]

    func serialize(to serializer: inout SQLSerializer) {
        SQLBind(self.values).serialize(to: &serializer)
        serializer.write("::vector")
    }
}

// MARK: - Sort by cosine distance

extension QueryBuilder {
    /// Adds an `ORDER BY` clause that sorts results by cosine distance to the given vector
    /// using PostgreSQL's `<=>` operator.
    ///
    /// This method only adds a sort expression — it does not select the distance as a
    /// computed column. Use ``allWithDistance(_:to:limit:)`` if you need the distance values.
    ///
    /// ```swift
    /// PageChunk.query(on: db)
    ///     .filter(...)
    ///     .sort(PageChunk().$embedding.key, cosineDistanceTo: queryVector)
    ///     .limit(10)
    ///     .all()
    /// ```
    ///
    /// - Parameters:
    ///   - fieldKey: The field key of the vector column.
    ///   - vector: The query vector to compare against.
    /// - Returns: `self` for chaining.
    @discardableResult
    public func sort(
        _ fieldKey: FieldKey,
        cosineDistanceTo vector: [Double]
    ) -> Self {
        let sortExpression = SQLOrderBy(
            expression: SQLBinaryExpression(
                left: SQLColumn(fieldKey.description),
                op: SQLRaw("<=>"),
                right: SQLVectorBinding(values: vector)
            ),
            direction: SQLDirection.ascending
        )
        return self.sort(.custom(sortExpression))
    }
}

// MARK: - Search with distance

extension QueryBuilder {
    /// Performs a semantic search using cosine distance, returning the models sorted by
    /// proximity to the query vector along with their computed distance values.
    ///
    /// This method uses the normal Fluent execution pipeline, adding the distance
    /// computation and ordering as custom fields and sorts on the ``DatabaseQuery``.
    ///
    /// Any filters previously applied to the query builder are preserved.
    ///
    /// ```swift
    /// let results = try await PageChunk.query(on: db)
    ///     .filter(...)
    ///     .allWithDistance(PageChunk().$embedding.key, to: queryVector, limit: 10)
    /// // results: [(PageChunk, Double)]
    /// ```
    ///
    /// - Parameters:
    ///   - fieldKey: The field key of the vector column to compare against.
    ///   - vector: The query vector.
    ///   - limit: The maximum number of results to return.
    /// - Returns: An array of `(Model, Double)` tuples, sorted by ascending distance.
    public func allWithDistance(
        _ fieldKey: FieldKey,
        to vector: [Double],
        limit: Int
    ) async throws -> [(Model, Double)] {
        // Build a copy of the query with the limit set.
        var query = self.query
        query.action = .read
        query.limits = [.count(limit)]

        // If no explicit fields were selected, add all model fields.
        if query.fields.isEmpty {
            query.fields = Model.keys.map { path in
                .extendedPath([path], schema: Model.schemaOrAlias, space: Model.spaceIfNotAliased)
            }
        }

        // Add columns from joined tables so that model.joined(OtherModel.self)
        // can hydrate them from the output.
        for join in query.joins {
            let (schema, alias): (String, String?)
            switch join {
            case .join(let s, let a, _, _, _):
                (schema, alias) = (s, a)
            case .extendedJoin(let s, _, let a, _, _, _):
                (schema, alias) = (s, a)
            case .advancedJoin(let s, _, let a, _, _):
                (schema, alias) = (s, a)
            case .custom:
                continue // skip custom joins — can't infer schema
            }
            let tableName = alias ?? schema
            query.fields.append(.custom(SQLColumn(SQLLiteral.all, table: SQLIdentifier(tableName))))
        }

        // Append the distance column: field <=> $vector::vector AS __pgvector_distance
        let fieldName = fieldKey.description
        query.fields.append(.custom(
            SQLAlias(
                SQLBinaryExpression(
                    left: SQLColumn(fieldName),
                    op: SQLRaw("<=>"),
                    right: SQLVectorBinding(values: vector)
                ),
                as: SQLIdentifier("__pgvector_distance")
            )
        ))

        // Order by the computed distance.
        query.sorts.append(.custom(SQLIdentifier("__pgvector_distance")))

        // Execute through the normal Fluent pipeline, which uses the database
        // driver's native DatabaseOutput — this handles schema-prefixed column
        // names correctly, unlike SQLDatabaseOutput.
        //
        // We accumulate raw outputs in the non-throwing closure, then decode
        // them outside where throwing is allowed.
        nonisolated(unsafe) var outputs = [any DatabaseOutput]()
        try await self.database.execute(query: query, onOutput: { output in
            outputs.append(output)
        })

        return try outputs.map { output in
            let model = Model()
            try model.output(from: output.qualifiedSchema(space: Model.spaceIfNotAliased, Model.schemaOrAlias))
            let distance = try output.decode(FieldKey(stringLiteral: "__pgvector_distance"), as: Double.self)
            return (model, distance)
        }
    }
}