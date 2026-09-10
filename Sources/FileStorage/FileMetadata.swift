import Foundation

/// Metadata describing a stored file, as reported by the storage backend.
public struct FileMetadata: Sendable, Equatable {
    /// The internet media type of the object (e.g. `"image/png"`).
    public var contentType: String?

    /// The `Content-Disposition` header value stored with the object.
    public var contentDisposition: String?

    /// The size of the object in bytes.
    public var contentLength: Int?

    /// The entity tag of the object, used for conditional requests and cache
    /// validation.
    public var etag: String?

    /// The date and time the object was last modified.
    public var lastModified: Date?

    /// Backend-specific metadata keyed by name (e.g. S3 `x-amz-meta-*` values).
    public var metadata: [String: String]

    /// Any additional backend-specific attributes, keyed by lowercased header
    /// name. This is an escape hatch for attributes without a dedicated field.
    public var custom: [String: String]

    /// Creates new file metadata.
    public init(
        contentType: String? = nil,
        contentDisposition: String? = nil,
        contentLength: Int? = nil,
        etag: String? = nil,
        lastModified: Date? = nil,
        metadata: [String: String] = [:],
        custom: [String: String] = [:]
    ) {
        self.contentType = contentType
        self.contentDisposition = contentDisposition
        self.contentLength = contentLength
        self.etag = etag
        self.lastModified = lastModified
        self.metadata = metadata
        self.custom = custom
    }
}