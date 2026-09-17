import Testing
import Foundation
@preconcurrency import FluentKit
@preconcurrency import XCTFluent
@preconcurrency import VaporUtilities
import Vapor

// MARK: - Test model

final class TodoItem: Model, @unchecked Sendable {
    static let schema = "todo_items"
    static let space: String? = nil
    static let alias: String? = nil
    typealias IDValue = UUID

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    @OptionalField(key: "note")
    var note: String?

    @Field(key: "is_done")
    var isDone: Bool

    @OptionalField(key: "owner_id")
    var ownerID: UUID?

    @OptionalField(key: "due_date")
    var dueDate: Date?

    required init() {}
}

// MARK: - Test DTOs

final class TodoCreate: FillableDTO<TodoItem>, @unchecked Sendable {
    @FillableField(\TodoItem.$title) var title: String??
    @FillableField(\TodoItem.$note) var note: String??
    @FillableField(\TodoItem.$isDone) var isDone: Bool??

    override func validate() throws {
        if let present = title, let title = present, title.count < 3 {
            throw Abort(.badRequest, reason: "Title must be at least 3 characters.")
        }
    }
}

final class TodoPatch: FillableDTO<TodoItem>, @unchecked Sendable {
    @FillableField(\TodoItem.$title) var title: String??
    @FillableField(\TodoItem.$ownerID, guarded: true) var ownerID: UUID??

    override func willApply(to todo: TodoItem, on database: any Database) async throws {
        if case .some(.some(let value)) = ownerID {
            guard try await TodoItem.find(value, on: database) != nil else {
                throw Abort(.badRequest, reason: "Unknown owner '\(value)'.")
            }
        }
        try todo.set(ownerID, to: \.$ownerID)
    }
}

final class TodoSchedule: FillableDTO<TodoItem>, @unchecked Sendable {
    nonisolated(unsafe) static let iso = ISO8601DateFormatter()

    static func parseDate(_ string: String) throws -> Date {
        guard let date = Self.iso.date(from: string) else {
            throw Abort(.badRequest, reason: "Invalid date '\(string)'.")
        }
        return date
    }

    @FillableField(\TodoItem.$dueDate, converting: { try TodoSchedule.parseDate($0) })
    var dueDate: String??
}

final class TodoIDPatch: FillableDTO<TodoItem>, @unchecked Sendable {
    @FillableField(\TodoItem.$title) var title: String??
    @FillableField(\TodoItem.$id) var id: UUID??
}

final class BadTodo: FillableDTO<TodoItem>, @unchecked Sendable {
    @FillableField(\TodoItem.$title) var title: String??

    override func validate() throws {
        throw Abort(.badRequest, reason: "nope")
    }
}

// MARK: - Decoding

@Test("decode distinguishes absent, null and value")
func testTripleStateDecoding() throws {
    let full = try JSONDecoder().decode(TodoCreate.self,
        from: Data(#"{"title":"Buy milk","note":"urgent","isDone":true}"#.utf8))
    #expect(full.title == "Buy milk")
    #expect(full.note == "urgent")
    #expect(full.isDone == true)
    #expect(full.presentKeys.map(\.description).sorted() == ["is_done", "note", "title"])

    let nulls = try JSONDecoder().decode(TodoCreate.self,
        from: Data(#"{"title":null,"note":null,"isDone":false}"#.utf8))
    #expect(nulls.title == .some(nil))        // present and null
    #expect(nulls.note == .some(nil))         // present and null
    #expect(nulls.isDone == false)
    #expect(nulls.presentKeys.map(\.description).sorted() == ["is_done", "note", "title"])

    let empty = try JSONDecoder().decode(TodoCreate.self, from: Data(#"{}"#.utf8))
    #expect(empty.title == nil)               // absent
    #expect(empty.note == nil)
    #expect(empty.presentKeys.isEmpty)
}

// MARK: - fill (in-memory)

@Test("fill applies only present values")
func testFillAppliesOnlyPresent() throws {
    let patch = try JSONDecoder().decode(TodoCreate.self, from: Data(#"{"title":"New title"}"#.utf8))
    let todo = TodoItem()
    todo.title = "Old"
    todo.note = "Keep me"
    todo.isDone = false

    try todo.fill(patch)

    #expect(todo.title == "New title")
    #expect(todo.note == "Keep me")           // absent → untouched
    #expect(todo.isDone == false)
    #expect(todo.$title.value == "New title") // input provenance → will save
    #expect(todo.$note.value == .some("Keep me"))
}

@Test("fill sets explicit null on optional columns")
func testFillWithNull() throws {
    let patch = try JSONDecoder().decode(TodoCreate.self, from: Data(#"{"note":null}"#.utf8))
    let todo = TodoItem()
    todo.title = "T"
    todo.note = "existing"
    todo.isDone = false

    try todo.fill(patch)

    #expect(todo.$note.value == .some(nil))   // explicit null pending
    #expect(todo.title == "T")                // untouched
}

@Test("fill rejects null for a required column")
func testFillRejectsNullForRequired() throws {
    let patch = try JSONDecoder().decode(TodoCreate.self, from: Data(#"{"title":null}"#.utf8))
    let todo = TodoItem()

    do {
        try todo.fill(patch)
        Issue.record("Expected an Abort error")
    } catch let error as Abort {
        #expect(error.status == .badRequest)
        #expect(error.reason.contains("title"))
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("fill rejects identifier fields")
func testFillRejectsIdentifier() throws {
    let patch = try JSONDecoder().decode(TodoIDPatch.self,
        from: Data(#"{"title":"x","id":"\#(UUID().uuidString)"}"#.utf8))
    let todo = TodoItem()

    do {
        try todo.fill(patch)
        Issue.record("Expected an Abort error")
    } catch let error as Abort {
        #expect(error.status == .badRequest)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("fill converts values through the converting closure")
func testFillConverts() throws {
    // ISO8601DateFormatter strips fractional seconds, so compare whole seconds.
    let date = try #require(TodoSchedule.iso.date(from: "2026-09-12T14:00:00Z"))
    let patch = try JSONDecoder().decode(TodoSchedule.self,
        from: Data(#"{"dueDate":"2026-09-12T14:00:00Z"}"#.utf8))
    let todo = TodoItem()

    try todo.fill(patch)

    #expect(todo.dueDate == date)
}

// MARK: - guarded fields + set helper

@Test("guarded fields are not auto-applied")
func testGuardedFieldsNotAutoApplied() throws {
    let id = UUID()
    let patch = try JSONDecoder().decode(TodoPatch.self,
        from: Data(#"{"ownerID":"\#(id.uuidString)"}"#.utf8))
    let todo = TodoItem()
    todo.title = "Existing"

    try todo.fill(patch)                      // sync: willApply does not run

    #expect(todo.ownerID == nil)              // guarded → untouched by fill
    #expect(patch.presentKeys.map(\.description).sorted() == ["owner_id"])
}

@Test("set helper honors absent, null and value")
func testSetHelper() throws {
    let todo = TodoItem()
    todo.note = "existing"

    // Values passed to set(_:to:) are normally the DTO's typed fields, which
    // pin the generic parameter — explicit locals do the same here.
    let absent: String?? = nil
    let null: String?? = .some(nil)

    try todo.set(absent, to: \.$note)             // absent → untouched
    #expect(todo.note == "existing")

    try todo.set(null, to: \.$note)               // null → NULL
    #expect(todo.$note.value == .some(nil))

    try todo.set(.some("new"), to: \.$note)      // value
    #expect(todo.note == "new")

    do {                                           // null on a required column
        try todo.set(null, to: \.$title)
        Issue.record("Expected an Abort error")
    } catch let error as Abort {
        #expect(error.status == .badRequest)
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

// MARK: - update (full pipeline)

@Test("update saves only the present keys")
func testUpdateWritesOnlyPresentKeys() async throws {
    nonisolated(unsafe) var captured: [FieldKey: DatabaseQuery.Value]?
    nonisolated(unsafe) var actions: [String] = []
    let db = CallbackTestDatabase { query in
        actions.append(query.action.name)
        if case .dictionary(let input) = query.input[0] {
            captured = input
        }
        return []
    }

    let todo = TodoItem()
    try todo.output(from: TodoRow(storage: [
        .id: UUID(),
        "title": "Old",
        "is_done": false,
    ]))

    let patch = try JSONDecoder().decode(TodoCreate.self, from: Data(#"{"title":"New"}"#.utf8))
    try await todo.update(patch, on: db.db)

    #expect(actions == ["update"])
    let input = try #require(captured)
    #expect(input.keys.map(\.description) == ["title"])
    #expect(todo.title == "New")
}

@Test("update with an empty body performs no query")
func testEmptyUpdateSkipsSave() async throws {
    nonisolated(unsafe) var executed = false
    let db = CallbackTestDatabase { _ in
        executed = true
        return []
    }

    let todo = TodoItem()
    try todo.output(from: TodoRow(storage: [
        .id: UUID(),
        "title": "Old",
        "is_done": false,
    ]))

    let patch = try JSONDecoder().decode(TodoCreate.self, from: Data(#"{}"#.utf8))
    try await todo.update(patch, on: db.db)

    #expect(!executed)
}

@Test("update on a fresh model creates it")
func testUpdateCreates() async throws {
    nonisolated(unsafe) var actions: [String] = []
    let db = CallbackTestDatabase { query in
        actions.append(query.action.name)
        return []
    }

    let todo = TodoItem()
    let patch = try JSONDecoder().decode(TodoCreate.self,
        from: Data(#"{"title":"New","isDone":true}"#.utf8))
    try await todo.update(patch, on: db.db)

    #expect(actions.contains("create"))
    #expect(todo.id != nil)
    #expect(todo.title == "New")
}

@Test("update runs willApply with the database")
func testUpdateWillApply() async throws {
    let ownerID = UUID()
    nonisolated(unsafe) var actions: [String] = []
    let db = CallbackTestDatabase { query in
        actions.append(query.action.name)
        if case .read = query.action {
            return [TodoRow(storage: [
                .id: ownerID,
                "title": "Old",
                "is_done": false,
            ])]
        }
        return []
    }

    let todo = TodoItem()
    try todo.output(from: TodoRow(storage: [
        .id: ownerID,
        "title": "Old",
        "is_done": false,
    ]))

    let patch = try JSONDecoder().decode(TodoPatch.self,
        from: Data(#"{"ownerID":"\#(ownerID.uuidString)"}"#.utf8))
    try await todo.update(patch, on: db.db)

    #expect(actions == ["read", "update"])    // existence check + save
    #expect(todo.ownerID == ownerID)
}

@Test("validation errors abort before any write")
func testValidationAbortsBeforeSave() async throws {
    nonisolated(unsafe) var executed = false
    let db = CallbackTestDatabase { _ in
        executed = true
        return []
    }

    let todo = TodoItem()
    todo.id = UUID()
    todo._$idExists = true

    let patch = try JSONDecoder().decode(BadTodo.self, from: Data(#"{"title":"x"}"#.utf8))
    do {
        try await todo.update(patch, on: db.db)
        Issue.record("Expected an Abort error")
    } catch let error as Abort {
        #expect(error.reason == "nope")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
    #expect(!executed)
}

// MARK: - Helpers

/// A minimal `DatabaseOutput` with proper per-key `contains`/`decodeNil`
/// semantics (unlike `TestOutput`, which reports every key as present).
private final class TodoRow: @unchecked Sendable, DatabaseOutput {
    let storage: [FieldKey: any Sendable]

    init(storage: [FieldKey: any Sendable]) {
        self.storage = storage
    }

    func schema(_ schema: String) -> any DatabaseOutput { self }
    func contains(_ key: FieldKey) -> Bool { storage[key] != nil }
    func decodeNil(_ key: FieldKey) throws -> Bool { storage[key] == nil }
    func decode<T>(_ key: FieldKey, as type: T.Type) throws -> T where T: Decodable {
        guard let value = storage[key] else { throw FluentError.missingField(name: key.description) }
        return value as! T
    }

    var description: String { "TodoRow" }
}

private extension DatabaseQuery.Action {
    var name: String {
        switch self {
        case .create: "create"
        case .read: "read"
        case .update: "update"
        case .delete: "delete"
        default: "other"
        }
    }
}