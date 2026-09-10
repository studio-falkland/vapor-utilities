import Foundation
import NIOCore
import Vapor

/// The HTTP method a presigned URL authorizes.
public enum PresignMethod: Sendable {
    /// Authorizes a `GET` (download) of the object.
    case get

    /// Authorizes a `PUT` (upload) of the object.
    case put
}

/// A streaming download of a stored file.
public struct FileStream: Sendable {
    /// The internet media type of the object, when reported by the backend.
    public var contentType: String?

    /// The `Content-Disposition` header value, when reported by the backend.
    public var contentDisposition: String?

    /// The size of the object in bytes, when known up front.
    public var contentLength: Int?

    /// The object's bytes.
    public var body: AsyncThrowingStream<ByteBuffer, Error>

    /// Creates a new file stream.
    public init(
        contentType: String? = nil,
        contentDisposition: String? = nil,
        contentLength: Int? = nil,
        body: AsyncThrowingStream<ByteBuffer, Error>
    ) {
        self.contentType = contentType
        self.contentDisposition = contentDisposition
        self.contentLength = contentLength
        self.body = body
    }
}

/// A storage backend capable of storing and retrieving files.
///
/// Conform to this protocol to add support for additional storage backends
/// (e.g. Google Cloud Storage, Azure Blob Storage, or local disk). Register a
/// backend with `app.fileStorages.use(...)` and access it from routes via
/// `req.fileStorage`.
public protocol FileStorageDriver: Sendable {
    /// Uploads raw bytes under the given key.
    func upload(data: Data, key: String, contentType: String?, disposition: String?, metadata: [String: String]) async throws

    /// Uploads a multipart file part under the given key.
    func upload(file: File, key: String, contentType: String?, disposition: String?, metadata: [String: String]) async throws

    /// Downloads the object at `key` into memory.
    func get(key: String) async throws -> Data

    /// Streams the object at `key`.
    func stream(key: String) async throws -> FileStream

    /// Returns a URL that grants temporary access to the object at `key`.
    ///
    /// - Parameters:
    ///   - key: The object key.
    ///   - method: Whether the URL authorizes a download or an upload.
    ///   - expiresIn: How long the URL remains valid.
    ///   - parameters: Additional query parameters to include in the signed
    ///     URL. For downloads these are treated as response overrides (e.g.
    ///     `response-content-type`, `response-content-disposition`).
    ///   - headers: Headers that must be sent with the request when using the
    ///     URL. They are signed and must match exactly.
    func presignedURL(key: String, method: PresignMethod, expiresIn: TimeAmount, parameters: [String: String], headers: HTTPHeaders) async throws -> URL

    /// Returns metadata for the object at `key`.
    func metadata(key: String) async throws -> FileMetadata

    /// Deletes the object at `key`.
    func delete(key: String) async throws

    /// Releases any resources held by the driver.
    ///
    /// Called during application shutdown. Drivers without resources to
    /// release do not need to implement this.
    func shutdown() async throws
}

extension FileStorageDriver {
    /// Default no-op implementation for drivers without resources to release.
    public func shutdown() async throws {}
}