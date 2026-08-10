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

// MARK: - Model decoding output

/// A `DatabaseOutput` that decodes model fields from a schema-qualified output
/// (so aliased columns like `"page_chunks_id"` are found) but delegates
/// `schema(_:)` to the unscoped output. This ensures that `cachedOutput`
/// stores the unscoped output, so `model.joined(OtherModel.self)` can
/// re-qualify it with the joined model's schema.
struct ModelDecodingOutput: DatabaseOutput {
    /// The schema-qualified output used for field lookups.
    let scoped: any DatabaseOutput
    /// The unscoped output used for `schema(_:)` delegation.
    let unscoped: any DatabaseOutput

    var description: String { "ModelDecodingOutput(\(self.scoped.description))" }

    func schema(_ schema: String) -> any DatabaseOutput {
        self.unscoped.schema(schema)
    }

    func contains(_ key: FieldKey) -> Bool {
        self.scoped.contains(key)
    }

    func decodeNil(_ key: FieldKey) throws -> Bool {
        try self.scoped.decodeNil(key)
    }

    func decode<T>(_ key: FieldKey, as type: T.Type) throws -> T where T: Decodable {
        try self.scoped.decode(key, as: T.self)
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

        // Ensure the pgvector type OID is registered before decoding.
        // This is a one-time query that caches the result in Vector.psqlType.
        try await FPGVector.registerVectorTypes(on: self.database)

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
            // Use a wrapper that decodes fields from the schema-qualified output
            // (so aliased columns like "page_chunks_scraped_page_id" are found),
            // but delegates schema() to the unscoped output so that
            // model.joined(OtherModel.self) can re-qualify correctly.
            let scoped = output.qualifiedSchema(space: Model.spaceIfNotAliased, Model.schemaOrAlias)
            try model.output(from: ModelDecodingOutput(scoped: scoped, unscoped: output))
            let distance = try output.decode(FieldKey(stringLiteral: "__pgvector_distance"), as: Double.self)
            return (model, distance)
        }
    }
}