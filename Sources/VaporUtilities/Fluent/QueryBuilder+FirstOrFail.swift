import FluentKit
import Vapor

extension QueryBuilder {
    /// Returns the first model matching the query, or throws an `Abort` error when
    /// no model is found.
    ///
    /// This is a convenience over ``first()`` that replaces the manual nil-check
    /// and `throw Abort(...)` boilerplate:
    ///
    /// ```swift
    /// // Before:
    /// guard let user = try await User.query(on: db)
    ///     .filter(\.$email == email)
    ///     .first() else {
    ///     throw Abort(.notFound, reason: "User not found")
    /// }
    ///
    /// // After:
    /// let user = try await User.query(on: db)
    ///     .filter(\.$email == email)
    ///     .firstOrFail()
    /// ```
    ///
    /// - Parameters:
    ///   - status: The HTTP status of the thrown `Abort`. Defaults to `.notFound`.
    ///   - reason: The reason of the thrown `Abort`. Defaults to `"<schema> not found"`
    ///     where `<schema>` is the model's schema name.
    /// - Returns: The first model matching the query.
    /// - Throws: An `Abort` error with the given `status` and `reason` when no model
    ///   matches the query.
    public func firstOrFail(
        status: HTTPResponseStatus = .notFound,
        reason: String? = nil
    ) async throws -> Model {
        guard let model = try await self.first() else {
            throw Abort(status, reason: reason ?? "\(Model.schema) not found")
        }
        return model
    }
}