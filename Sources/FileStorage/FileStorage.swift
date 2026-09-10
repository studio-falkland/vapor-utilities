import Foundation
import NIOCore
import Vapor

extension Request {
    /// The default file storage driver.
    ///
    /// ```swift
    /// let data = try await req.fileStorage.get(key: "avatars/\(user.id).png")
    /// ```
    public var fileStorage: FileStorage {
        self.fileStorage(.default)
    }

    /// The file storage driver registered under the given identifier.
    ///
    /// ```swift
    /// try await req.fileStorage(.init(string: "archives")).get(key: "backup.tar.gz")
    /// ```
    public func fileStorage(_ id: FileStorageID) -> FileStorage {
        .init(driver: self.application.fileStorages.require(id))
    }
}

/// A friendly, driver-agnostic interface for storing and retrieving files.
///
/// Obtain an instance from a request:
///
/// ```swift
/// let storage = req.fileStorage
///
/// try await storage.upload(data: data, key: "photos/\(id).jpg", contentType: "image/jpeg")
/// let signed = try await storage.presignedURL(key: "photos/\(id).jpg", method: .get, expiresIn: .hours(1))
/// ```
public struct FileStorage: Sendable {
    /// The underlying driver.
    let driver: any FileStorageDriver

    /// Creates a new `FileStorage` backed by the given driver.
    public init(driver: any FileStorageDriver) {
        self.driver = driver
    }

    /// Uploads raw bytes under the given key.
    ///
    /// - Parameters:
    ///   - data: The bytes to upload.
    ///   - key: The key to store the object under.
    ///   - contentType: Optional `Content-Type` stored with the object.
    ///   - disposition: Optional `Content-Disposition` stored with the object.
    ///   - metadata: Optional backend metadata stored with the object.
    public func upload(
        data: Data,
        key: String,
        contentType: String? = nil,
        disposition: String? = nil,
        metadata: [String: String] = [:]
    ) async throws {
        try await self.driver.upload(
            data: data,
            key: key,
            contentType: contentType,
            disposition: disposition,
            metadata: metadata
        )
    }

    /// Uploads a multipart file part under the given key.
    ///
    /// When `contentType` is `nil`, the file's own content type is used.
    public func upload(
        file: File,
        key: String,
        contentType: String? = nil,
        disposition: String? = nil,
        metadata: [String: String] = [:]
    ) async throws {
        try await self.driver.upload(
            file: file,
            key: key,
            contentType: contentType,
            disposition: disposition,
            metadata: metadata
        )
    }

    /// Downloads the object at `key` into memory.
    public func get(key: String) async throws -> Data {
        try await self.driver.get(key: key)
    }

    /// Streams the object at `key` as a Vapor `Response`.
    ///
    /// The response carries the object's content type, content disposition,
    /// and content length when the backend reports them.
    public func stream(key: String) async throws -> Response {
        let stream = try await self.driver.stream(key: key)
        let response = Response(
            status: .ok,
            headers: [:],
            body: .init(managedAsyncStream: { writer in
                do {
                    for try await buffer in stream.body {
                        try await writer.write(.buffer(buffer))
                    }
                    try await writer.write(.end)
                } catch {
                    try await writer.write(.error(error))
                }
            })
        )
        if let contentType = stream.contentType {
            response.headers.replaceOrAdd(name: .contentType, value: contentType)
        }
        if let contentDisposition = stream.contentDisposition {
            response.headers.replaceOrAdd(name: "Content-Disposition", value: contentDisposition)
        }
        if let contentLength = stream.contentLength {
            response.headers.replaceOrAdd(name: .contentLength, value: String(contentLength))
        }
        return response
    }

    /// Returns a URL that grants temporary access to the object at `key`.
    ///
    /// - Parameters:
    ///   - key: The object key.
    ///   - method: Whether the URL authorizes a download (`get`) or an upload (`put`).
    ///   - expiresIn: How long the URL remains valid.
    ///   - parameters: Additional query parameters to include in the signed
    ///     URL. For downloads these are treated as response overrides (e.g.
    ///     `response-content-type`, `response-content-disposition`).
    ///   - headers: Headers that must be sent with the request when using the
    ///     URL. They are signed and must match exactly (most commonly needed
    ///     for uploads, e.g. `Content-Type`).
    ///
    /// ```swift
    /// // Download URL that overrides the stored content type and disposition
    /// let url = try await req.fileStorage.presignedURL(
    ///     key: "reports/june.pdf",
    ///     method: .get,
    ///     expiresIn: .hours(1),
    ///     parameters: [
    ///         "response-content-type": "application/pdf",
    ///         "response-content-disposition": "attachment; filename=\"june.pdf\""
    ///     ]
    /// )
    ///
    /// // Upload URL that requires a matching Content-Type header
    /// let url = try await req.fileStorage.presignedURL(
    ///     key: "drafts/\(id).json",
    ///     method: .put,
    ///     expiresIn: .minutes(15),
    ///     headers: ["Content-Type": "application/json"]
    /// )
    /// ```
    public func presignedURL(
        key: String,
        method: PresignMethod,
        expiresIn: TimeAmount,
        parameters: [String: String] = [:],
        headers: HTTPHeaders = [:]
    ) async throws -> URL {
        try await self.driver.presignedURL(
            key: key,
            method: method,
            expiresIn: expiresIn,
            parameters: parameters,
            headers: headers
        )
    }

    /// Returns metadata for the object at `key`.
    public func metadata(key: String) async throws -> FileMetadata {
        try await self.driver.metadata(key: key)
    }

    /// Deletes the object at `key`.
    public func delete(key: String) async throws {
        try await self.driver.delete(key: key)
    }
}