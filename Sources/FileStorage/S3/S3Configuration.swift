import Foundation
import SotoS3

/// Configuration for the Amazon S3 file storage driver.
///
/// ```swift
/// app.fileStorages.use(.s3(.init(
///     bucket: "acme-uploads",
///     region: .eucentral1,
///     accessKeyId: Environment.get("S3_ACCESS_KEY_ID") ?? "",
///     secretAccessKey: Environment.get("S3_SECRET_ACCESS_KEY") ?? "",
///     endpoint: Environment.get("S3_ENDPOINT").flatMap(URL.init(string:))
/// )))
/// ```
public struct S3Configuration: Sendable {
    /// The name of the bucket objects are stored in.
    public var bucket: String

    /// The AWS region the bucket resides in.
    ///
    /// For S3-compatible providers that accept a custom region name, use
    /// `Region.other(_:)` (e.g. `Region.other("auto")` for Cloudflare R2).
    public var region: Region

    /// The access key ID used to sign requests.
    public var accessKeyId: String

    /// The secret access key used to sign requests.
    public var secretAccessKey: String

    /// A custom endpoint for S3-compatible providers (e.g. Cloudflare R2,
    /// MinIO, or DigitalOcean Spaces). When set, objects are addressed with
    /// path-style URLs against this endpoint. When `nil`, objects are
    /// addressed with virtual-hosted URLs against AWS S3.
    public var endpoint: URL?

    /// Creates a new S3 configuration.
    public init(
        bucket: String,
        region: Region,
        accessKeyId: String,
        secretAccessKey: String,
        endpoint: URL? = nil
    ) {
        self.bucket = bucket
        self.region = region
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.endpoint = endpoint
    }
}