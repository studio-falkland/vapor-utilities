import FluentKit
import SQLKit

/// Errors thrown by `Database.renameField(_:to:on:)`.
public enum RenameFieldError: Error, Equatable, Sendable {
    /// The database does not conform to `SQLDatabase`, so it cannot emit `ALTER TABLE` statements.
    case notSQLDatabase

    /// The dialect does not support the `ALTER TABLE ... RENAME COLUMN ...` syntax.
    /// The associated value is the dialect's reported name.
    case unsupportedDialect(String)
}

extension Database {
    /// Renames a column in the given table by emitting a single dialect-aware
    /// `ALTER TABLE ... RENAME COLUMN ... TO ...` statement.
    ///
    /// Only the database column is renamed; update the corresponding model
    /// property (and its `@Field(key:)`) separately.
    ///
    /// Supported dialects:
    /// - PostgreSQL (all versions)
    /// - MySQL 8.0+ (`RENAME COLUMN` is unavailable on MySQL 5.7 and earlier,
    ///   which require `CHANGE COLUMN` plus the full column definition)
    /// - SQLite 3.25+ (older SQLite cannot rename columns at all)
    ///
    /// - Parameters:
    ///   - oldName: The current name of the column.
    ///   - newName: The name to rename the column to.
    ///   - schema: The name of the table containing the column.
    /// - Throws: `RenameFieldError.notSQLDatabase` if the database is not SQL-backed;
    ///   `RenameFieldError.unsupportedDialect(_:)` if the dialect does not support
    ///   column renames.
    public func renameField(_ oldName: FieldKey, to newName: FieldKey, on schema: String) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw RenameFieldError.notSQLDatabase
        }

        let dialectName = sql.dialect.name.lowercased()
        guard ["postgresql", "mysql", "sqlite"].contains(where: { dialectName.contains($0) }) else {
            throw RenameFieldError.unsupportedDialect(sql.dialect.name)
        }

        try await sql.raw(
            "ALTER TABLE \(ident: schema) RENAME COLUMN \(ident: oldName.description) TO \(ident: newName.description)"
        ).run()
    }
}
