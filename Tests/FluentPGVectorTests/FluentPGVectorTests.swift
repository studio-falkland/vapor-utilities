import Testing
import Foundation
@preconcurrency import FluentKit
@preconcurrency import FluentPGVector
import SQLKit
import XCTFluent
import NIOEmbedded
import NIOCore
import Logging

// MARK: - VectorProperty Tests

@Test("VectorProperty stores and retrieves values")
func testVectorProperty() {
    let prop = VectorProperty<VectorTestModel>(key: .string("embedding"), dimensions: 2560)
    #expect(prop.dimensions == 2560)
    #expect(prop.key == .string("embedding"))
    #expect(prop.wrappedValue == nil)

    prop.wrappedValue = [0.1, 0.2, 0.3]
    #expect(prop.wrappedValue == [0.1, 0.2, 0.3])
}

@Test("DatabaseSchema.DataType.vector creates correct type")
func testVectorDataType() {
    let dataType = DatabaseSchema.DataType.vector(dimensions: 2560)
    if case .custom(let value) = dataType {
        let description = "\(value)"
        #expect(description.contains("vector(2560)"))
    } else {
        Issue.record("Expected .custom data type")
    }
}

// MARK: - Test Model

final class VectorTestModel: Model, @unchecked Sendable {
    static let schema = "test_models"
    static let space: String? = nil
    static let alias: String? = nil

    typealias IDValue = UUID

    @ID(key: .id)
    var id: UUID?

    @Vector(key: .string("embedding"), dimensions: 2560)
    var embedding: [Double]?

    required init() {}
}

// MARK: - VectorProperty Protocol Conformance Tests

@Test("VectorProperty conforms to AnyProperty")
func testAnyPropertyConformance() {
    let prop = VectorProperty<VectorTestModel>(key: .string("embedding"), dimensions: 2560)
    let anyProp: any AnyProperty = prop
    #expect(anyProp.anyValue == nil)
    #expect(type(of: anyProp).anyValueType == [Double]?.self)
}

@Test("VectorProperty conforms to QueryableProperty")
func testQueryablePropertyConformance() {
    let prop = VectorProperty<VectorTestModel>(key: .string("embedding"), dimensions: 2560)
    let queryable: any AnyQueryableProperty = prop
    #expect(queryable.path == [FieldKey(stringLiteral: "embedding")])
}

@Test("VectorProperty conforms to CustomStringConvertible")
func testCustomStringConvertible() {
    let prop = VectorProperty<VectorTestModel>(key: .string("embedding"), dimensions: 2560)
    let description = prop.description
    #expect(description.contains("Vector"))
    #expect(description.contains("embedding"))
    #expect(description.contains("2560"))
}

// MARK: - sort(cosineDistanceTo:) Tests

@Test("sort adds a custom sort with <=> operator and ::vector cast")
func testSortCosineDistance() async throws {
    let db = CallbackTestDatabase { query in
        #expect(query.sorts.count == 1)
        guard case .custom(let sortExpr) = query.sorts[0],
              let sqlExpr = sortExpr as? any SQLExpression
        else {
            Issue.record("Expected .custom sort with SQLExpression")
            return []
        }
        let sql = serializeForTest(sqlExpr)
        #expect(sql.contains("<=>"))
        #expect(sql.contains("::vector"))
        #expect(sql.contains("ASC"))
        return []
    }

    let builder = VectorTestModel.query(on: db.db)
    builder.sort(VectorTestModel().$embedding.key, cosineDistanceTo: [0.1, 0.2, 0.3])
    _ = try await builder.all().get()
}

@Test("sort does not add explicit fields")
func testSortDoesNotModifyFields() {
    let db = CallbackTestDatabase { _ in [] }
    let builder = VectorTestModel.query(on: db.db)
    builder.sort(VectorTestModel().$embedding.key, cosineDistanceTo: [0.1, 0.2, 0.3])
    #expect(builder.query.sorts.count == 1)
    #expect(builder.query.fields.isEmpty)
}

// MARK: - allWithDistance Tests

@Test("allWithDistance generates SQL with <=>, ::vector, distance alias, table, LIMIT, ORDER BY")
func testAllWithDistanceQuery() async throws {
    let db = TestDB()
    let builder = VectorTestModel.query(on: db)
    _ = try? await builder.allWithDistance(
        VectorTestModel().$embedding.key,
        to: [0.1, 0.2, 0.3],
        limit: 10
    )

    let sql = db.sql
    #expect(sql?.contains("<=>") == true)
    #expect(sql?.contains("::vector") == true)
    #expect(sql?.contains("__pgvector_distance") == true)
    #expect(sql?.contains("test_models") == true)
    #expect(sql?.contains("LIMIT") == true)
    #expect(sql?.contains("ORDER BY") == true)
}

@Test("allWithDistance respects the given limit")
func testAllWithDistanceLimit() async throws {
    let db = TestDB()
    let builder = VectorTestModel.query(on: db)
    _ = try? await builder.allWithDistance(
        VectorTestModel().$embedding.key,
        to: [0.1, 0.2, 0.3],
        limit: 5
    )
    #expect(db.sql?.contains("LIMIT 5") == true)
}

@Test("allWithDistance returns empty array when no rows are produced")
func testAllWithDistanceEmptyResult() async throws {
    let db = TestDB()
    let builder = VectorTestModel.query(on: db)
    let results = try? await builder.allWithDistance(
        VectorTestModel().$embedding.key,
        to: [0.1, 0.2, 0.3],
        limit: 10
    )
    #expect(results?.isEmpty == true)
}

// MARK: - allWithDistance with Join Tests

final class JoinParentModel: Model, @unchecked Sendable {
    static let schema = "join_parents"
    static let space: String? = nil
    static let alias: String? = nil

    typealias IDValue = UUID

    @ID(key: .id)
    var id: UUID?

    @Field(key: "name")
    var name: String

    required init() {}
}

final class JoinChildModel: Model, @unchecked Sendable {
    static let schema = "join_children"
    static let space: String? = nil
    static let alias: String? = nil

    typealias IDValue = UUID

    @ID(key: .id)
    var id: UUID?

    @Vector(key: .string("embedding"), dimensions: 128)
    var embedding: [Double]?

    @Parent(key: "parent_id")
    var parent: JoinParentModel

    required init() {}
}

@Test("allWithDistance with join includes joined table.* columns in SQL")
func testAllWithDistanceJoinIncludesJoinedColumns() async throws {
    let db = TestDB()
    let builder = JoinChildModel.query(on: db)
        .join(JoinParentModel.self, on: \JoinChildModel.$parent.$id == \JoinParentModel.$id)
        .filter(JoinParentModel.self, \JoinParentModel.$name == "test")

    _ = try? await builder.allWithDistance(
        JoinChildModel().$embedding.key,
        to: [0.1, 0.2],
        limit: 5
    )

    guard let sql = db.sql else {
        Issue.record("No SQL was captured")
        return
    }

    // Joined table should appear as "table_name.*"
    #expect(sql.contains(#""join_parents".*"#))

    // Primary model fields should be listed explicitly
    #expect(sql.contains("join_children"))

    // Distance infrastructure should still be present
    #expect(sql.contains("__pgvector_distance"))
    #expect(sql.contains("<=>"))
    #expect(sql.contains("::vector"))
    #expect(sql.contains("LIMIT 5"))
    #expect(sql.contains("ORDER BY"))
}

// MARK: - Round-trip test helpers

/// A minimal `SQLRow` that stores values keyed by column name.
struct JoinTestRow: SQLRow, @unchecked Sendable {
    let data: [String: any Sendable]

    var allColumns: [String] { Array(data.keys) }

    func contains(column: String) -> Bool {
        data.keys.contains(column)
    }

    func decodeNil(column: String) throws -> Bool {
        data[column] == nil
    }

    func decode<D: Decodable>(column: String, as: D.Type) throws -> D {
        guard let value = data[column] else {
            throw DecodingError.keyNotFound(
                AnyCodingKey(stringValue: column),
                DecodingError.Context(codingPath: [], debugDescription: "Column '\(column)' not found")
            )
        }
        guard let typed = value as? D else {
            throw DecodingError.typeMismatch(
                D.self,
                DecodingError.Context(codingPath: [], debugDescription: "Expected \(D.self) for column '\(column)', got \(type(of: value))")
            )
        }
        return typed
    }
}

struct AnyCodingKey: CodingKey, @unchecked Sendable {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// A `TestDB` variant that returns a pre-built row instead of capturing SQL.
final class TestDBWithRow: Database, SQLDatabase, @unchecked Sendable {
    let logger = Logger(label: "test")
    let eventLoop: any EventLoop = NIOAsyncTestingEventLoop()
    let dialect: any SQLDialect = PostgreSQLStyleDialect()
    let queryLogLevel: Logger.Level? = nil
    var context: DatabaseContext
    var inTransaction: Bool { false }

    let row: any SQLRow

    init(row: any SQLRow) {
        self.row = row
        self.context = DatabaseContext(
            configuration: _Config(),
            logger: Logger(label: "test"),
            eventLoop: NIOAsyncTestingEventLoop()
        )
    }

    // MARK: SQLDatabase

    func execute(sql query: any SQLExpression, _ onRow: @escaping @Sendable (any SQLRow) -> ()) -> EventLoopFuture<Void> {
        onRow(self.row)
        return eventLoop.makeSucceededFuture(())
    }

    func execute(sql query: any SQLExpression, _ onRow: @escaping @Sendable (any SQLRow) -> ()) async throws {
        onRow(self.row)
    }

    // MARK: Database

    func execute(query: DatabaseQuery, onOutput: @escaping @Sendable (any DatabaseOutput) -> ()) -> EventLoopFuture<Void> {
        eventLoop.makeSucceededFuture(())
    }
    func execute(schema: DatabaseSchema) -> EventLoopFuture<Void> { eventLoop.makeSucceededFuture(()) }
    func execute(enum: DatabaseEnum) -> EventLoopFuture<Void> { eventLoop.makeSucceededFuture(()) }
    func transaction<T>(_ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> { closure(self) }
    func withConnection<T>(_ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> { closure(self) }
}

@Test("allWithDistance with join produces model that can decode joined model")
func testAllWithDistanceJoinDecodesJoinedModel() async throws {
    let parentID = UUID()
    let childID = parentID // same ID since both models share the "id" column name

    let row = JoinTestRow(data: [
        "id": childID,
        "embedding": [0.1, 0.2],
        "parent_id": parentID,
        "name": "test-parent",
        "__pgvector_distance": 0.5,
    ])

    let db = TestDBWithRow(row: row)
    let builder = JoinChildModel.query(on: db)
        .join(JoinParentModel.self, on: \JoinChildModel.$parent.$id == \JoinParentModel.$id)

    let results = try await builder.allWithDistance(
        JoinChildModel().$embedding.key,
        to: [0.1, 0.2],
        limit: 5
    )

    #expect(results.count == 1)
    let (child, distance) = results[0]
    #expect(child.id == childID)
    #expect(distance == 0.5)

    // This is the crucial assertion: the joined model should be decodable
    // from the same row. Before the fix, this would crash with:
    // "Cannot access field before it is initialized or fetched: name"
    let parent = try child.joined(JoinParentModel.self)
    #expect(parent.id == parentID)
    #expect(parent.name == "test-parent")
}

// MARK: - Test Helpers

/// Serialize an `SQLExpression` to a SQL string for test assertions.
private func serializeForTest(_ expression: any SQLExpression) -> String {
    let db = TestDB()
    return db.serialize(expression).sql
}

/// A `Database` + `SQLDatabase` mock that captures the last SQL string.
///
/// FluentKit's own `DummyDatabaseForTestSQLSerializer` does the same thing,
/// but it's in a test target and not importable.
final class TestDB: Database, SQLDatabase, @unchecked Sendable {
    let logger = Logger(label: "test")
    let eventLoop: any EventLoop = NIOAsyncTestingEventLoop()
    let dialect: any SQLDialect = PostgreSQLStyleDialect()
    let queryLogLevel: Logger.Level? = nil
    var context: DatabaseContext
    var inTransaction: Bool { false }

    private(set) var sql: String?

    init() {
        self.context = DatabaseContext(
            configuration: _Config(),
            logger: Logger(label: "test"),
            eventLoop: NIOAsyncTestingEventLoop()
        )
    }

    // MARK: SQLDatabase

    func execute(sql query: any SQLExpression, _ onRow: @escaping @Sendable (any SQLRow) -> ()) -> EventLoopFuture<Void> {
        sql = serialize(query).sql
        return eventLoop.makeSucceededFuture(())
    }

    func execute(sql query: any SQLExpression, _ onRow: @escaping @Sendable (any SQLRow) -> ()) async throws {
        sql = serialize(query).sql
    }

    // MARK: Database

    func execute(query: DatabaseQuery, onOutput: @escaping @Sendable (any DatabaseOutput) -> ()) -> EventLoopFuture<Void> {
        eventLoop.makeSucceededFuture(())
    }
    func execute(schema: DatabaseSchema) -> EventLoopFuture<Void> { eventLoop.makeSucceededFuture(()) }
    func execute(enum: DatabaseEnum) -> EventLoopFuture<Void> { eventLoop.makeSucceededFuture(()) }
    func transaction<T>(_ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> { closure(self) }
    func withConnection<T>(_ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> { closure(self) }
}

/// PostgreSQL-style dialect for SQL serialization in tests.
private struct PostgreSQLStyleDialect: SQLDialect {
    var name: String { "psql" }
    var identifierQuote: any SQLExpression { SQLRaw("\"") }
    var literalStringQuote: any SQLExpression { SQLRaw("'") }
    var supportsAutoIncrement: Bool { true }
    var autoIncrementClause: any SQLExpression { SQLRaw("GENERATED BY DEFAULT AS IDENTITY") }
    var autoIncrementFunction: (any SQLExpression)? { nil }
    var literalDefault: any SQLExpression { SQLRaw("DEFAULT") }
    var supportsIfExists: Bool { true }
    var enumSyntax: SQLEnumSyntax { .unsupported }
    var supportsDropBehavior: Bool { true }
    var supportsReturning: Bool { true }
    var triggerSyntax: SQLTriggerSyntax { .init() }
    var alterTableSyntax: SQLAlterTableSyntax { .init() }
    var upsertSyntax: SQLUpsertSyntax { .unsupported }
    var unionFeatures: SQLUnionFeatures { [] }
    var sharedSelectLockExpression: (any SQLExpression)? { SQLRaw("FOR SHARE") }
    var exclusiveSelectLockExpression: (any SQLExpression)? { SQLRaw("FOR UPDATE") }

    func bindPlaceholder(at position: Int) -> any SQLExpression { SQLRaw("$\(position)") }
    func literalBoolean(_ value: Bool) -> any SQLExpression { SQLRaw(value ? "true" : "false") }
    func customDataType(for: SQLDataType) -> (any SQLExpression)? { nil }
    func normalizeSQLConstraint(identifier: any SQLExpression) -> any SQLExpression { identifier }
    func nestedSubpathExpression(in column: any SQLExpression, for path: [String]) -> (any SQLExpression)? { nil }
}

private struct _Config: DatabaseConfiguration {
    var middleware: [any AnyModelMiddleware] = []
    func makeDriver(for databases: Databases) -> any DatabaseDriver {
        struct D: DatabaseDriver {
            func makeDatabase(with context: DatabaseContext) -> any Database { TestDB() }
            func shutdown() {}
        }
        return D()
    }
}