import Vapor

extension Parameters {
    /// Returns the value of the named path parameter, or throws an `Abort` error
    /// when the parameter is missing.
    ///
    /// This is a convenience over ``get(_:)`` that replaces the manual nil-check
    /// and `throw Abort(...)` boilerplate:
    ///
    /// ```swift
    /// // Before:
    /// guard let userID = req.parameters.get("userID") else {
    ///     throw Abort(.badRequest, reason: "Missing required parameter 'userID'")
    /// }
    ///
    /// // After:
    /// let userID = try req.parameters.require("userID")
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the path parameter to retrieve.
    ///   - status: The HTTP status of the thrown `Abort`. Defaults to `.badRequest`.
    ///   - reason: The reason of the thrown `Abort`. Defaults to
    ///     `"Missing required parameter '<name>'"`.
    /// - Returns: The value of the path parameter.
    /// - Throws: An `Abort` error with the given `status` and `reason` when the
    ///   parameter is missing.
    public func require(
        _ name: String,
        status: HTTPResponseStatus = .badRequest,
        reason: String? = nil
    ) throws -> String {
        guard let value = self.get(name) else {
            throw Abort(status, reason: reason ?? "Missing required parameter '\(name)'")
        }
        return value
    }

    /// Returns the value of the named path parameter cast to the given type, or
    /// throws an `Abort` error when the parameter is missing or cannot be cast.
    ///
    /// Works with any `LosslessStringConvertible` type, such as `Int`, `Double`,
    /// or `Bool`:
    ///
    /// ```swift
    /// let page = try req.parameters.require("page", as: Int.self)
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the path parameter to retrieve.
    ///   - type: The type to cast the parameter value to.
    ///   - status: The HTTP status of the thrown `Abort`. Defaults to `.badRequest`.
    ///   - reason: The reason of the thrown `Abort`. Defaults to
    ///     `"Missing required parameter '<name>'"` when the parameter is absent, or
    ///     `"Invalid value for parameter '<name>'"` when it cannot be cast.
    /// - Returns: The value of the path parameter cast to `T`.
    /// - Throws: An `Abort` error with the given `status` and `reason` when the
    ///   parameter is missing or cannot be cast to `T`.
    public func require<T: LosslessStringConvertible>(
        _ name: String,
        as type: T.Type = T.self,
        status: HTTPResponseStatus = .badRequest,
        reason: String? = nil
    ) throws -> T {
        guard let raw = self.get(name) else {
            throw Abort(status, reason: reason ?? "Missing required parameter '\(name)'")
        }
        guard let value = T(raw) else {
            throw Abort(status, reason: reason ?? "Invalid value for parameter '\(name)'")
        }
        return value
    }

    /// Returns the value of the named path parameter as a `UUID`, or throws an
    /// `Abort` error when the parameter is missing or is not a valid UUID.
    ///
    /// `UUID` does not conform to `LosslessStringConvertible`, so it cannot be
    /// used with ``require(_:as:status:reason:)``; use this method instead:
    ///
    /// ```swift
    /// let user = try await User.findOrFail(
    ///     req.parameters.requireUUID("userID"),
    ///     on: req.db
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the path parameter to retrieve.
    ///   - status: The HTTP status of the thrown `Abort`. Defaults to `.badRequest`.
    ///   - reason: The reason of the thrown `Abort`. Defaults to
    ///     `"Missing required parameter '<name>'"` when the parameter is absent, or
    ///     `"Invalid UUID for parameter '<name>'"` when it is not a valid UUID.
    /// - Returns: The value of the path parameter as a `UUID`.
    /// - Throws: An `Abort` error with the given `status` and `reason` when the
    ///   parameter is missing or is not a valid UUID.
    public func requireUUID(
        _ name: String,
        status: HTTPResponseStatus = .badRequest,
        reason: String? = nil
    ) throws -> UUID {
        guard let raw = self.get(name) else {
            throw Abort(status, reason: reason ?? "Missing required parameter '\(name)'")
        }
        guard let value = UUID(uuidString: raw) else {
            throw Abort(status, reason: reason ?? "Invalid UUID for parameter '\(name)'")
        }
        return value
    }
}