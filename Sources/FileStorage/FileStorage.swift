import Foundation
import HTTPTypes
import Vapor

/// A friendly, driver-agnostic interface for storing and retrieving files.
///
/// Obtain an instance from the registry:
///
/// ```swift
/// let storage = fileStorages.storage()
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
        var response = Response(status: .ok, headers: [:], body: stream.body)
        if let contentType = stream.contentType {
            response.headers[.contentType] = contentType
        }
        if let contentDisposition = stream.contentDisposition {
            response.headers[.contentDisposition] = contentDisposition
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
    public func presignedURL(
        key: String,
        method: PresignMethod,
        expiresIn: Duration,
        parameters: [String: String] = [:],
        headers: HTTPFields = [:]
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

extension FileStorages {
    /// Returns a ``FileStorage`` facade for the driver registered under `id`.
    ///
    /// - Parameter id: The identifier of the driver to use.
    /// - Returns: A facade backed by the driver.
    public func storage(_ id: FileStorageID = .default) -> FileStorage {
        FileStorage(driver: self.require(id))
    }
}
