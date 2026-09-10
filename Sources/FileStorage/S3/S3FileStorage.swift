import Foundation
import NIOCore
import NIOFoundationCompat
import SotoS3
import Vapor

/// A ``FileStorageDriver`` backed by Amazon S3, or any S3-compatible endpoint.
///
/// Register it in `configure.swift`:
///
/// ```swift
/// app.fileStorages.use(.s3(.init(
///     bucket: "acme-uploads",
///     region: .euCentral1,
///     accessKeyId: Environment.get("S3_ACCESS_KEY_ID") ?? "",
///     secretAccessKey: Environment.get("S3_SECRET_ACCESS_KEY") ?? ""
/// )))
/// ```
public struct S3FileStorage: FileStorageDriver {
    /// The Soto S3 client.
    let s3: S3

    /// The bucket objects are stored in.
    let bucket: String

    /// The region used when addressing objects and signing requests.
    let region: Region

    /// The custom endpoint, when an S3-compatible provider is used.
    let endpoint: URL?

    /// Creates a new S3-backed driver.
    public init(s3: S3, bucket: String, region: Region, endpoint: URL? = nil) {
        self.s3 = s3
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
    }

    // MARK: - Upload

    public func upload(data: Data, key: String, contentType: String?, disposition: String?, metadata: [String: String]) async throws {
        do {
            _ = try await self.s3.putObject(
                body: AWSHTTPBody(bytes: data),
                bucket: self.bucket,
                contentDisposition: disposition,
                contentType: contentType,
                key: key,
                metadata: metadata.isEmpty ? nil : metadata
            )
        } catch {
            throw Self.mapError(error, key: key)
        }
    }

    public func upload(file: File, key: String, contentType: String?, disposition: String?, metadata: [String: String]) async throws {
        let fileContentType = contentType ?? file.contentType?.serialize()
        try await self.upload(
            data: Data(buffer: file.data),
            key: key,
            contentType: fileContentType,
            disposition: disposition,
            metadata: metadata
        )
    }

    // MARK: - Download

    public func get(key: String) async throws -> Data {
        do {
            let response = try await self.s3.getObject(bucket: self.bucket, key: key)
            return Data(buffer: try await response.body.collect(upTo: .max))
        } catch {
            throw Self.mapError(error, key: key)
        }
    }

    public func stream(key: String) async throws -> FileStream {
        do {
            let response = try await self.s3.getObject(bucket: self.bucket, key: key)
            let body = response.body
            return FileStream(
                contentType: response.contentType,
                contentDisposition: response.contentDisposition,
                contentLength: response.contentLength.flatMap(Int.init),
                body: AsyncThrowingStream { continuation in
                    let task = Task {
                        do {
                            for try await buffer in body {
                                continuation.yield(buffer)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: Self.mapError(error, key: key))
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            )
        } catch {
            throw Self.mapError(error, key: key)
        }
    }

    // MARK: - Presigned URLs

    public func presignedURL(
        key: String,
        method: PresignMethod,
        expiresIn: TimeAmount,
        parameters: [String: String],
        headers: HTTPHeaders
    ) async throws -> URL {
        guard var components = URLComponents(url: self.objectURL(key: key), resolvingAgainstBaseURL: false) else {
            throw StorageError.invalidRequest(reason: "Unable to build object URL for key '\(key)'")
        }
        if !parameters.isEmpty {
            var queryItems = components.queryItems ?? []
            queryItems.append(contentsOf: parameters.map { URLQueryItem(name: $0.key, value: $0.value) })
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw StorageError.invalidRequest(reason: "Unable to build object URL for key '\(key)'")
        }
        do {
            return try await self.s3.signURL(
                url: url,
                httpMethod: method == .get ? .GET : .PUT,
                headers: headers,
                expires: expiresIn
            )
        } catch {
            throw Self.mapError(error, key: key)
        }
    }

    // MARK: - Inspection & deletion

    public func metadata(key: String) async throws -> FileMetadata {
        do {
            let response = try await self.s3.headObject(bucket: self.bucket, key: key)
            return FileMetadata(
                contentType: response.contentType,
                contentDisposition: response.contentDisposition,
                contentLength: response.contentLength.flatMap(Int.init),
                etag: response.eTag,
                lastModified: response.lastModified,
                metadata: response.metadata ?? [:],
                custom: [
                    "cache-control": response.cacheControl,
                    "content-encoding": response.contentEncoding,
                    "content-language": response.contentLanguage,
                    "storage-class": response.storageClass?.rawValue,
                    "version-id": response.versionId,
                ].compactMapValues { $0 }
            )
        } catch {
            throw Self.mapError(error, key: key)
        }
    }

    public func delete(key: String) async throws {
        do {
            _ = try await self.s3.deleteObject(bucket: self.bucket, key: key)
        } catch {
            throw Self.mapError(error, key: key)
        }
    }

    // MARK: - Shutdown

    /// Shuts down the underlying Soto client (its credential provider).
    public func shutdown() async throws {
        try await self.s3.client.shutdown()
    }

    // MARK: - URL building

    /// Builds the unsigned base URL for an object.
    ///
    /// Uses virtual-hosted addressing (`https://<bucket>.s3.<region>.amazonaws.com/<key>`)
    /// for AWS, and path-style addressing (`https://<endpoint>/<bucket>/<key>`) for
    /// custom endpoints.
    func objectURL(key: String) -> URL {
        if let endpoint {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
                ?? URLComponents(string: "/")!
            // Ensure the path starts with a slash; URLComponents drops a
            // slash-less path when building the URL.
            var path = components.path
            if path.isEmpty {
                path = "/"
            } else if !path.hasSuffix("/") {
                path += "/"
            }
            components.path = path + self.bucket + "/" + key
            return components.url ?? endpoint
        } else {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "\(self.bucket).s3.\(self.region.rawValue).amazonaws.com"
            components.path = "/" + key
            return components.url ?? URL(string: "/")!
        }
    }

    // MARK: - Error mapping

    /// Translates Soto errors into ``StorageError`` cases, mapping the common
    /// S3 failures and wrapping everything else with available context.
    static func mapError(_ error: Error, key: String) -> Error {
        if let awsError = error as? any AWSErrorType {
            switch awsError.errorCode {
            case "NoSuchKey", "NotFound":
                return StorageError.notFound(key: key)
            case "AccessDenied", "InvalidAccessKeyId", "SignatureDoesNotMatch":
                return StorageError.accessDenied(key: key)
            case "NoSuchBucket":
                return StorageError.invalidRequest(reason: "Bucket does not exist or is not accessible")
            default:
                return StorageError.failure(StorageFailure(
                    status: awsError.context.map { Int($0.responseCode.code) },
                    code: awsError.errorCode,
                    message: awsError.context?.message ?? String(describing: error),
                    requestID: awsError.context?.headers.first(name: "x-amz-request-id")
                ))
            }
        }
        return StorageError.failure(StorageFailure(message: String(describing: error)))
    }
}

// MARK: - Configuration factory

extension FileStorageConfigurationFactory {
    /// Creates an S3-backed file storage driver from the given configuration.
    ///
    /// The driver reuses the application's shared `AsyncHTTPClient`, so no
    /// separate connection pool is created.
    public static func s3(_ configuration: S3Configuration) -> FileStorageConfigurationFactory {
        .init { application in
            let client = AWSClient(
                credentialProvider: .static(
                    accessKeyId: configuration.accessKeyId,
                    secretAccessKey: configuration.secretAccessKey
                ),
                httpClient: application.http.client.shared,
                logger: application.logger
            )
            let s3 = S3(
                client: client,
                region: configuration.region,
                endpoint: configuration.endpoint?.absoluteString
            )
            return S3FileStorage(
                s3: s3,
                bucket: configuration.bucket,
                region: configuration.region,
                endpoint: configuration.endpoint
            )
        }
    }
}