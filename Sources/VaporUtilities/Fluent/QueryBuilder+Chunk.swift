import FluentKit

/// Errors thrown by the chunk query methods.
enum FluentChunkError: Error, CustomStringConvertible {
    case unsupportedCustomSortDirection

    var description: String {
        switch self {
        case .unsupportedCustomSortDirection:
            "FluentChunkError: Custom sort directions are not supported for cursor-based chunking."
        }
    }
}

extension QueryBuilder where Model: FluentKit.Model {

    /// Iterates through query results in chunks of the given size, processing each
    /// chunk with the provided closure before fetching the next.
    ///
    /// Uses `offset`/`limit` pagination internally. For large datasets, prefer the
    /// cursor-based ``chunk(size:cursor:order:_:)`` overload which avoids the
    /// performance degradation of large offsets.
    ///
    /// > Tip: Apply a `sort` before calling this method to ensure consistent ordering
    /// > across pages. Without a sort, the order is undefined.
    ///
    /// ```swift
    /// try await User.query(on: db)
    ///     .sort(\.$id, .ascending)
    ///     .chunk(size: 100) { chunk in
    ///         for user in chunk {
    ///             // process each user
    ///         }
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - size: The number of records to fetch per chunk.
    ///   - closure: An async closure that receives each chunk of records.
    public func chunk(size: Int, _ closure: @Sendable @escaping ([Model]) async throws -> Void) async throws {
        var offset = 0
        var results: [Model]

        repeat {
            results = try await self.limit(size).offset(offset).all()
            if !results.isEmpty {
                try await closure(results)
            }
            offset += size
        } while results.count == size
    }

    /// Iterates through query results in chunks using a cursor column, processing
    /// each chunk with the provided closure before fetching the next.
    ///
    /// Uses `WHERE cursor > ? ORDER BY cursor LIMIT ?` internally, which avoids the
    /// performance degradation of large offsets.
    ///
    /// The cursor column value type must be `Comparable` (e.g. `Int`, `Date`, `String`, or `UUID`).
    /// `UUID` conforms to `Comparable` on macOS 14+ / iOS 17+.
    ///
    /// ```swift
    /// try await User.query(on: db)
    ///     .filter(\.$status == "active")
    ///     .chunk(size: 100, cursor: \.$id, order: .ascending) { chunk in
    ///         for user in chunk {
    ///             // process each user
    ///         }
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - size: The number of records to fetch per chunk.
    ///   - cursor: A key path to a ``QueryableProperty`` to use as the cursor
    ///     (e.g. `\\.$id`, `\\.$createdAt`).
    ///   - order: The sort direction for the cursor column. Defaults to `.ascending`.
    ///   - closure: An async closure that receives each chunk of records.
    public func chunk<P: QueryableProperty>(
        size: Int,
        cursor: KeyPath<Model, P>,
        order: DatabaseQuery.Sort.Direction = .ascending,
        _ closure: @Sendable @escaping ([Model]) async throws -> Void
    ) async throws where P.Model == Model, P.Value: Comparable {
        let fieldPath = Model.path(for: cursor)

        let method: DatabaseQuery.Filter.Method
        switch order {
        case .ascending:
            method = .greaterThan
        case .descending:
            method = .lessThan
        case .custom:
            throw FluentChunkError.unsupportedCustomSortDirection
        }

        // Save a base copy to derive each iteration's query from,
        // preserving any user-applied filters, joins, etc.
        let base = self.copy()

        var lastValue: P.Value? = nil
        var results: [Model]

        repeat {
            let query = base.copy()
            query.sort(cursor, order)
            query.limit(size)

            if let last = lastValue {
                query.filter(fieldPath, method, last)
            }

            results = try await query.all()

            if !results.isEmpty {
                try await closure(results)
                lastValue = results.last![keyPath: cursor].value
            }
        } while results.count == size
    }

    /// A convenience for ``chunk(size:cursor:order:_:)`` that uses the model's
    /// default ID column as the cursor.
    ///
    /// ```swift
    /// try await User.query(on: db)
    ///     .filter(\.$status == "active")
    ///     .chunkById(size: 100) { chunk in
    ///         for user in chunk {
    ///             // process each user
    ///         }
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - size: The number of records to fetch per chunk.
    ///   - order: The sort direction for the ID column. Defaults to `.ascending`.
    ///   - closure: An async closure that receives each chunk of records.
    public func chunkById(
        size: Int,
        order: DatabaseQuery.Sort.Direction = .ascending,
        _ closure: @Sendable @escaping ([Model]) async throws -> Void
    ) async throws where Model.IDValue: Comparable {
        try await self.chunk(size: size, cursor: \._$id, order: order, closure)
    }
}