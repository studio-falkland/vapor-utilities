import FluentKit
import SQLKit

extension DatabaseSchema.DataType {
    /// Creates a `vector(dimensions)` column type for use with pgvector.
    ///
    /// Use this in migrations to declare a column with the pgvector `vector` type:
    ///
    /// ```swift
    /// try await database.schema("page_chunks")
    ///     .field("embedding", .vector(dimensions: 2560))
    ///     .create()
    /// ```
    public static func vector(dimensions: Int) -> DatabaseSchema.DataType {
        .custom(SQLRaw("vector(\(dimensions))"))
    }
}