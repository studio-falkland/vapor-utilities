import Testing
import Foundation
import Vapor
import VaporUtilities

// MARK: - require

@Test("require returns the raw parameter value")
func testRequireReturnsValue() throws {
    var parameters = Parameters()
    parameters.set("userID", to: "123")
    #expect(try parameters.require("userID") == "123")
}

@Test("require throws Abort(.badRequest) when the parameter is missing")
func testRequireThrowsMissing() throws {
    var parameters = Parameters()
    parameters.set("otherID", to: "123")

    do {
        _ = try parameters.require("userID")
        Issue.record("Expected require to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .badRequest)
        #expect(error.reason == "Missing required parameter 'userID'")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("require throws an Abort with a custom status and reason")
func testRequireCustomStatusAndReason() throws {
    var parameters = Parameters()
    parameters.set("otherID", to: "123")

    do {
        _ = try parameters.require("userID", status: .notFound, reason: "User not found")
        Issue.record("Expected require to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .notFound)
        #expect(error.reason == "User not found")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

// MARK: - require(_:as:)

@Test("require(_:as:) returns the typed parameter value")
func testRequireTypedValue() throws {
    var parameters = Parameters()
    parameters.set("page", to: "42")
    #expect(try parameters.require("page", as: Int.self) == 42)
}

@Test("require(_:as:) infers the type from context")
func testRequireTypedInference() throws {
    var parameters = Parameters()
    parameters.set("page", to: "7")
    let page: Int = try parameters.require("page")
    #expect(page == 7)
}

@Test("require(_:as:) throws Abort(.badRequest) when the value is not parseable")
func testRequireTypedInvalid() throws {
    var parameters = Parameters()
    parameters.set("page", to: "not-a-number")

    do {
        _ = try parameters.require("page", as: Int.self)
        Issue.record("Expected require to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .badRequest)
        #expect(error.reason == "Invalid value for parameter 'page'")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("require(_:as:) throws Abort(.badRequest) when the parameter is missing")
func testRequireTypedMissing() throws {
    var parameters = Parameters()

    do {
        _ = try parameters.require("page", as: Int.self)
        Issue.record("Expected require to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .badRequest)
        #expect(error.reason == "Missing required parameter 'page'")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

// MARK: - requireUUID

@Test("requireUUID returns the UUID value")
func testRequireUUIDReturnsValue() throws {
    var parameters = Parameters()
    let id = UUID()
    parameters.set("userID", to: id.uuidString)
    #expect(try parameters.requireUUID("userID") == id)
}

@Test("requireUUID throws Abort(.badRequest) when the value is not a valid UUID")
func testRequireUUIDInvalid() throws {
    var parameters = Parameters()
    parameters.set("userID", to: "not-a-uuid")

    do {
        _ = try parameters.requireUUID("userID")
        Issue.record("Expected requireUUID to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .badRequest)
        #expect(error.reason == "Invalid UUID for parameter 'userID'")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("requireUUID throws Abort(.badRequest) when the parameter is missing")
func testRequireUUIDMissing() throws {
    var parameters = Parameters()

    do {
        _ = try parameters.requireUUID("userID")
        Issue.record("Expected requireUUID to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .badRequest)
        #expect(error.reason == "Missing required parameter 'userID'")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}

@Test("requireUUID throws an Abort with a custom status and reason")
func testRequireUUIDCustomStatusAndReason() throws {
    var parameters = Parameters()
    parameters.set("userID", to: "not-a-uuid")

    do {
        _ = try parameters.requireUUID("userID", status: .notFound, reason: "User not found")
        Issue.record("Expected requireUUID to throw an Abort error")
    } catch let error as Abort {
        #expect(error.status == .notFound)
        #expect(error.reason == "User not found")
    } catch {
        Issue.record("Unexpected error type: \(error)")
    }
}