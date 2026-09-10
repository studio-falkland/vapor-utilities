import FluentKit
import Vapor

extension FluentKit.Model {
    /// Returns the model with the given ID, or throws an `Abort` error when no
    /// model with that ID exists.
    ///
    /// This is a convenience over ``FluentKit/Model/find(_:on:)`` that replaces the
    /// manual nil-check and `throw Abort(...)` boilerplate:
    ///
    /// ```swift
    /// // Before:
    /// guard let user = try await User.find(req.parameters.get("userID"), on: req.db) else {
    ///     throw Abort(.notFound, reason: "User not found")
    /// }
    ///
    /// // After:
    /// let user = try await User.findOrFail(req.parameters.get("userID"), on: req.db)
    /// ```
    ///
    /// - Parameters:
    ///   - id: The ID of the model to find, or `nil` (which throws immediately).
    ///   - database: The database to query.
    ///   - status: The HTTP status of the thrown `Abort`. Defaults to `.notFound`.
    ///   - reason: The reason of the thrown `Abort`. Defaults to `"<schema> not found"`
    ///     where `<schema>` is the model's schema name.
    /// - Returns: The model with the given ID.
    /// - Throws: An `Abort` error with the given `status` and `reason` when no model
    ///   with the given ID exists.
    public static func findOrFail(
        _ id: Self.IDValue?,
        on database: any Database,
        status: HTTPResponseStatus = .notFound,
        reason: String? = nil
    ) async throws -> Self {
        guard let model = try await Self.find(id, on: database) else {
            throw Abort(status, reason: reason ?? "\(Self.schema) not found")
        }
        return model
    }
}