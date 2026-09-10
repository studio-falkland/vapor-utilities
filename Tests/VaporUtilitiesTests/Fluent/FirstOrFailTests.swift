import Testing
import Foundation
@preconcurrency import FluentKit
@preconcurrency import XCTFluent
@preconcurrency import VaporUtilities
import Vapor

// MARK: - Test Model

final class Todo: Model, @unchecked Sendable {
    static let schema = "todos"
    static let space: String? = nil
    static let alias: String? = nil

    typealias IDValue = UUID

    @ID(key: .id)
    var id: UUID?

    @Field(key: "title")
    var title: String

    required init() {}
}

// MARK: - firstOrFail

@Test("firstOrFail returns the first matching model")
func testFirstOrFailReturnsModel() async throws {
    let db = ArrayTestDatabase()
    let todo = Todo()
    todo.id = UUID()
    todo.title = "Buy milk"
    db.append([todo])

    let result = try await Todo.query(on: db.db).firstOrFail()

    #expect(result.id == todo.id)
    #expect(result.title == "Buy milk")
}

@Test("firstOrFail returns the first model when multiple match")
func testFirstOrFailReturnsFirstModel() async throws {
    let db = ArrayTestDatabase()
    let first = Todo()
    first.id = UUID()
    first.title = "First"
    let second = Todo()
    second.id = UUID()
    second.title = "Second"
    db.append([first, second])

    let result = try await Todo.query(on: db.db).firstOrFail()

    #expect(result.id == first.id)
}

@Test("firstOrFail throws Abort(.notFound) when no model matches")
func testFirstOrFailThrowsNotFound() async throws {
    let db = ArrayTestDatabase()
    db.append([])

    do {
        _ = try await Todo.query(on: db.db).firstOrFail()
        Issue.record("Expected firstOrFail to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .notFound)
        #expect(error.reason == "todos not found")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("firstOrFail throws an Abort with a custom status and reason")
func testFirstOrFailCustomStatusAndReason() async throws {
    let db = ArrayTestDatabase()
    db.append([])

    do {
        _ = try await Todo.query(on: db.db)
            .firstOrFail(status: .notFound, reason: "No todo with that identifier exists")
        Issue.record("Expected firstOrFail to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .notFound)
        #expect(error.reason == "No todo with that identifier exists")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("firstOrFail preserves the applied filters")
func testFirstOrFailPreservesFilters() async throws {
    let db = ArrayTestDatabase()
    let todo = Todo()
    todo.id = UUID()
    todo.title = "Buy milk"
    db.append([todo])

    let result = try await Todo.query(on: db.db)
        .filter(\.$title == "Buy milk")
        .firstOrFail()

    #expect(result.title == "Buy milk")
}

// MARK: - findOrFail

@Test("findOrFail returns the model with the given ID")
func testFindOrFailReturnsModel() async throws {
    let db = ArrayTestDatabase()
    let todo = Todo()
    todo.id = UUID()
    todo.title = "Buy milk"
    db.append([todo])

    let result = try await Todo.findOrFail(todo.id, on: db.db)

    #expect(result.id == todo.id)
    #expect(result.title == "Buy milk")
}

@Test("findOrFail throws Abort(.notFound) when no model has the given ID")
func testFindOrFailThrowsNotFound() async throws {
    let db = ArrayTestDatabase()
    db.append([])

    do {
        _ = try await Todo.findOrFail(UUID(), on: db.db)
        Issue.record("Expected findOrFail to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .notFound)
        #expect(error.reason == "todos not found")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("findOrFail throws an Abort with a custom status and reason")
func testFindOrFailCustomStatusAndReason() async throws {
    let db = ArrayTestDatabase()
    db.append([])

    do {
        _ = try await Todo.findOrFail(
            UUID(),
            on: db.db,
            status: .notFound,
            reason: "No todo with that identifier exists"
        )
        Issue.record("Expected findOrFail to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .notFound)
        #expect(error.reason == "No todo with that identifier exists")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("findOrFail with a nil ID throws Abort(.notFound)")
func testFindOrFailNilID() async throws {
    let db = ArrayTestDatabase()
    db.append([])

    do {
        _ = try await Todo.findOrFail(nil, on: db.db)
        Issue.record("Expected findOrFail to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .notFound)
        #expect(error.reason == "todos not found")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}