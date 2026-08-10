import FluentKit
import FluentSQL
@preconcurrency import Pgvector
@preconcurrency import PgvectorNIO
import PostgresNIO

/// Namespace for pgvector integration helpers.
public enum FPGVector {
    /// Registers the pgvector type OIDs with the PostgresNIO decoding system.
    ///
    /// Call this once during app startup so that ``VectorProperty`` can decode
    /// `vector` columns in any query — not just those using ``allWithDistance(_:to:limit:)``.
    ///
    /// The pgvector `vector` type has a dynamically-assigned OID that differs per
    /// database. The ``Pgvector/Vector`` type's ``PostgresDecodable`` conformance
    /// requires this OID to be set before decoding can work. This method queries
    /// the OID and caches it in a static variable for the lifetime of the process.
    ///
    /// ```swift
    /// // In configure.swift:
    /// try await FPGVector.registerVectorTypes(on: app.db)
    /// ```
    ///
    /// > Note: ``allWithDistance(_:to:limit:)`` calls this automatically, so the
    /// > registration is always covered for similarity search queries. For regular
    /// > ``FluentKit/QueryBuilder/all()`` calls that select a `VectorProperty` column,
    /// > you must call this method once during setup.
    ///
    /// - Parameter database: Any Fluent database connected to a PostgreSQL server
    ///   with the pgvector extension installed.
    public static func registerVectorTypes(on database: Database) async throws {
        guard Pgvector.Vector.psqlType == nil else { return }

        guard let sql = database as? any SQLDatabase else {
            throw Error("Database does not support SQL queries")
        }

        let rows = try await sql.raw("SELECT regtype('vector')::oid::integer AS vector_oid")
            .all()
            .get()

        guard let row = rows.first else {
            throw Error("pgvector type 'vector' not found in the database")
        }

        guard let oid = try? row.decode(column: "vector_oid", as: Int.self) else {
            throw Error("could not decode vector OID from database response")
        }

        Pgvector.Vector.psqlType = PostgresDataType(UInt32(oid))
    }
}

// MARK: - Error

extension FPGVector {
    /// An error that occurs during pgvector type registration.
    public struct Error: Swift.Error, CustomStringConvertible, Sendable {
        public let description: String
        public init(_ description: String) {
            self.description = description
        }
    }
}

// MARK: - Test support

#if DEBUG
extension FPGVector {
    /// Pre-registers the pgvector OID for testing without a database query.
    /// The OID value is arbitrary; it just needs to be non-nil to skip the
    /// registration query in ``registerVectorTypes(on:)``.
    static func registerVectorTypesForTesting() {
        Pgvector.Vector.psqlType = PostgresDataType(UInt32(570820))
    }
}
#endif