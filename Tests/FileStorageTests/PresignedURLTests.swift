import Foundation
import Testing
import Vapor
import SotoS3
@testable import FileStorage

// MARK: - Helpers

private func withApp(_ body: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    try await body(app)
    try await app.asyncShutdown()
}

private func s3App(_ app: Application, endpoint: URL? = nil, region: Region = .eucentral1) {
    app.fileStorages.use(.s3(.init(
        bucket: "acme-uploads",
        region: region,
        accessKeyId: "AKIAACCESSKEY",
        secretAccessKey: "secret-key-value",
        endpoint: endpoint
    )))
}

private func makeRequest(_ app: Application) -> Request {
    Request(application: app, method: .GET, url: URI(path: "/"), on: app.eventLoopGroup.next())
}

// MARK: - Presigned URLs

@Test("presigned GET URL uses virtual-hosted AWS addressing", .timeLimit(.minutes(2)))
func presignedGETAWSAddressing() async throws {
    try await withApp { app in
        s3App(app)
        let url = try await makeRequest(app).fileStorage.presignedURL(
            key: "reports/june.pdf",
            method: .get,
            expiresIn: .minutes(15)
        )
        #expect(url.scheme == "https")
        #expect(url.host == "acme-uploads.s3.eu-central-1.amazonaws.com")
        #expect(url.path == "/reports/june.pdf")
        #expect(url.query?.contains("X-Amz-Signature=") == true)
    }
}

@Test("presigned URL signs custom response parameters", .timeLimit(.minutes(2)))
func presignedCustomParameters() async throws {
    try await withApp { app in
        s3App(app)
        let url = try await makeRequest(app).fileStorage.presignedURL(
            key: "reports/june.pdf",
            method: .get,
            expiresIn: .minutes(15),
            parameters: [
                "response-content-type": "application/pdf",
                "response-content-disposition": "attachment; filename=\"june.pdf\"",
            ]
        )
        let query = url.query ?? ""
        #expect(query.contains("X-Amz-Algorithm=AWS4-HMAC-SHA256"))
        #expect(query.contains("X-Amz-Credential=AKIAACCESSKEY%2F"))
        #expect(query.contains("X-Amz-Expires=900"))
        #expect(query.contains("X-Amz-Date="))
        #expect(query.contains("X-Amz-SignedHeaders=host"))
        #expect(query.contains("X-Amz-Signature="))
        #expect(query.contains("response-content-type=application%2Fpdf"))
        #expect(query.contains("response-content-disposition="))
    }
}

@Test("presigned PUT URL signs supplied headers", .timeLimit(.minutes(2)))
func presignedPUTSignedHeaders() async throws {
    try await withApp { app in
        s3App(app)
        let url = try await makeRequest(app).fileStorage.presignedURL(
            key: "drafts/\(UUID()).json",
            method: .put,
            expiresIn: .minutes(15),
            headers: ["Content-Type": "application/json"]
        )
        let query = url.query ?? ""
        #expect(query.contains("X-Amz-Signature="))
        // Both the content-type header and the host must be signed for a PUT.
        #expect(query.contains("X-Amz-SignedHeaders=content-type%3Bhost"))
    }
}

@Test("presigned URL uses path-style addressing with a custom endpoint", .timeLimit(.minutes(2)))
func presignedCustomEndpoint() async throws {
    try await withApp { app in
        s3App(app, endpoint: URL(string: "https://acctid.r2.cloudflarestorage.com"), region: .other("auto"))
        let url = try await makeRequest(app).fileStorage.presignedURL(
            key: "photos/avatar.png",
            method: .get,
            expiresIn: .hours(1)
        )
        #expect(url.host == "acctid.r2.cloudflarestorage.com")
        #expect(url.path == "/acme-uploads/photos/avatar.png")
        let query = url.query ?? ""
        #expect(query.contains("X-Amz-Credential=AKIAACCESSKEY%2F"))
        #expect(query.contains("%2Fauto%2Fs3%2Faws4_request") == true)
        #expect(query.contains("X-Amz-Signature="))
    }
}

// MARK: - Error mapping

@Test("maps no-such-key errors to StorageError.notFound")
func mapsNoSuchKey() throws {
    let error = S3FileStorage.mapError(AWSResponseError(errorCode: "NoSuchKey"), key: "missing.txt")
    // - always catchable as StorageError
    let storageError = try #require(error as? StorageError)
    guard case .notFound(let key) = storageError else {
        Issue.record("expected .notFound, got \(storageError)")
        return
    }
    #expect(key == "missing.txt")
}

@Test("maps access-denied errors to StorageError.accessDenied")
func mapsAccessDenied() throws {
    let error = S3FileStorage.mapError(AWSClientError.accessDenied, key: "secret.txt")
    let storageError = try #require(error as? StorageError)
    guard case .accessDenied(let key) = storageError else {
        Issue.record("expected .accessDenied, got \(storageError)")
        return
    }
    #expect(key == "secret.txt")
}

@Test("wraps unknown errors with context")
func wrapsUnknownErrors() throws {
    struct SomeError: Error, CustomStringConvertible {
        var description: String { "something exploded" }
    }
    let error = S3FileStorage.mapError(SomeError(), key: "x")
    let storageError = try #require(error as? StorageError)
    guard case .failure(let failure) = storageError else {
        Issue.record("expected .failure, got \(storageError)")
        return
    }
    #expect(failure.message?.contains("something exploded") == true)
}