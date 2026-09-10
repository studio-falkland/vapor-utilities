import Foundation

/// Details about a storage failure that is not one of the common error cases.
public struct StorageFailure: Sendable, Equatable {
    /// The HTTP status code returned by the backend, if available.
    public var status: Int?

    /// Backend-specific error code (e.g. `"NoSuchKey"`).
    public var code: String?

    /// A human-readable description of the failure.
    public var message: String?

    /// The backend request identifier, useful when filing support tickets.
    public var requestID: String?

    /// Creates a new storage failure.
    public init(status: Int? = nil, code: String? = nil, message: String? = nil, requestID: String? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.requestID = requestID
    }
}

/// Errors thrown by ``FileStorage`` operations.
///
/// Drivers translate backend-specific failures into these cases, with the
/// common cases named so callers can pattern-match directly:
///
/// ```swift
/// do {
///     try await req.fileStorage.get(key: key)
/// } catch StorageError.notFound {
///     throw Abort(.notFound)
/// } catch {
///     // log and rethrow
/// }
/// ```
public enum StorageError: Error, Sendable {
    /// The object does not exist.
    case notFound(key: String)

    /// The credentials lack permission to perform the operation.
    case accessDenied(key: String)

    /// The request was malformed or otherwise rejected by the backend.
    case invalidRequest(reason: String)

    /// Any other failure, wrapped with the context that is available.
    case failure(StorageFailure)
}