import Foundation
import HTTPTypes
import Testing
import Vapor
@testable import FileStorage

// MARK: - Helpers

/// A minimal in-memory driver used to exercise the registry without a backend.
actor StubDriver: FileStorageDriver {
    var uploadedData: [(data: Data, key: String, contentType: String?)] = []
    var deletedKeys: [String] = []
    var shutdownCount = 0
    var presignedURLs: [String] = []

    func upload(data: Data, key: String, contentType: String?, disposition: String?, metadata: [String: String]) async throws {
        self.uploadedData.append((data, key, contentType))
    }

    func upload(file: File, key: String, contentType: String?, disposition: String?, metadata: [String: String]) async throws {
        try await self.upload(
            data: Data(file.data.readableBytesView),
            key: key,
            contentType: contentType ?? file.contentType?.serialize(),
            disposition: disposition,
            metadata: metadata
        )
    }

    func get(key: String) async throws -> Data {
        Data("hello".utf8)
    }

    func stream(key: String) async throws -> FileStream {
        FileStream(
            contentType: "text/plain",
            contentLength: 5,
            body: Response.Body(data: Data("hello".utf8))
        )
    }

    func presignedURL(key: String, method: PresignMethod, expiresIn: Duration, parameters: [String: String], headers: HTTPFields) async throws -> URL {
        let signed = parameters.isEmpty ? key : "\(key)?\(parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&"))"
        self.presignedURLs.append(signed)
        return URL(string: "https://example.com/\(signed)")!
    }

    func metadata(key: String) async throws -> FileMetadata {
        FileMetadata(contentType: "text/plain", metadata: ["origin": "stub"])
    }

    func delete(key: String) async throws {
        self.deletedKeys.append(key)
    }

    func shutdown() async throws {
        self.shutdownCount += 1
    }
}

/// Thread-safe counter used to count factory invocations from concurrent tasks.
private final class StubFactoryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        self.lock.lock()
        self.count += 1
        self.lock.unlock()
    }

    var value: Int {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.count
    }
}

// MARK: - Registry

@Test("use registers the default driver and require returns it", .timeLimit(.minutes(2)))
func registryDefaultDriver() async throws {
    let stub = StubDriver()
    let fileStorages = FileStorages()
    fileStorages.use(.init { _ in stub })
    let required = fileStorages.require()
    #expect(required as? StubDriver === stub)
}

@Test("drivers registered under a named id are returned by require(id)", .timeLimit(.minutes(2)))
func registryNamedDriver() async throws {
    let stub = StubDriver()
    let fileStorages = FileStorages()
    let id = FileStorageID(string: "archives")
    fileStorages.use(.init { _ in stub }, as: id)
    #expect(fileStorages.require(id) as? StubDriver === stub)
}

@Test("require builds a driver at most once", .timeLimit(.minutes(2)))
func registryDriverIsLazyAndCached() async throws {
    let stub = StubDriver()
    let fileStorages = FileStorages()
    fileStorages.use(.init { _ in stub })
    #expect((fileStorages.require() as? StubDriver) === (fileStorages.require() as? StubDriver))
}

@Test("storage() routes to the default driver", .timeLimit(.minutes(2)))
func storageAccess() async throws {
    let stub = StubDriver()
    let fileStorages = FileStorages()
    fileStorages.use(.init { _ in stub })

    let fs = fileStorages.storage()
    try await fs.upload(data: Data("bytes".utf8), key: "a/b.txt", contentType: "text/plain")
    let uploaded = await stub.uploadedData
    #expect(uploaded.count == 1)
    #expect(uploaded[0].key == "a/b.txt")
    #expect(uploaded[0].contentType == "text/plain")
    #expect(uploaded[0].data == Data("bytes".utf8))
}

@Test("storage(id:) routes to a named driver", .timeLimit(.minutes(2)))
func storageNamedAccess() async throws {
    let stub = StubDriver()
    let fileStorages = FileStorages()
    let id = FileStorageID(string: "archives")
    fileStorages.use(.init { _ in stub }, as: id)

    let fs = fileStorages.storage(id)
    try await fs.delete(key: "old.tar.gz")
    let deleted = await stub.deletedKeys
    #expect(deleted == ["old.tar.gz"])
}

@Test("drivers are shut down during registry shutdown", .timeLimit(.minutes(2)))
func registryDriversShutDown() async throws {
    let stub = StubDriver()
    let fileStorages = FileStorages()
    fileStorages.use(.init { _ in stub })
    _ = fileStorages.require()
    await fileStorages.shutdown()
    let count = await stub.shutdownCount
    #expect(count == 1)
}

@Test("concurrent first access builds exactly one shared driver", .timeLimit(.minutes(2)))
func registryConcurrentFirstAccessBuildsOnce() async throws {
    let counter = StubFactoryCounter()
    let stub = StubDriver()
    let fileStorages = FileStorages()
    fileStorages.use(.init { _ in
        counter.increment()
        return stub
    })

    let required: [any FileStorageDriver] = await withTaskGroup(
        of: (any FileStorageDriver).self,
        returning: [any FileStorageDriver].self
    ) { group in
        for _ in 0..<32 {
            group.addTask { fileStorages.require() }
        }
        var drivers: [any FileStorageDriver] = []
        for await driver in group {
            drivers.append(driver)
        }
        return drivers
    }

    #expect(counter.value == 1)
    #expect(required.count == 32)
    for driver in required {
        #expect(driver as? StubDriver === stub)
    }
}

// MARK: - Façade

@Test("upload(file:) uses the file content type when none is given", .timeLimit(.minutes(2)))
func facadeUploadsFile() async throws {
    let stub = StubDriver()
    let fileStorages = FileStorages()
    fileStorages.use(.init { _ in stub })

    let file = File(data: "pdf", filename: "report.pdf")
    try await fileStorages.storage().upload(file: file, key: "docs/report.pdf")
    let uploaded = await stub.uploadedData
    #expect(uploaded.count == 1)
    #expect(uploaded[0].contentType == "application/pdf")
    #expect(uploaded[0].data == Data("pdf".utf8))
}

@Test("presignedURL forwards parameters and headers to the driver", .timeLimit(.minutes(2)))
func facadePresignedURL() async throws {
    let stub = StubDriver()
    let fileStorages = FileStorages()
    fileStorages.use(.init { _ in stub })

    var headers = HTTPFields()
    headers[.contentType] = "image/png"

    let url = try await fileStorages.storage().presignedURL(
        key: "x.png",
        method: .get,
        expiresIn: .seconds(300),
        parameters: ["response-content-type": "image/png"],
        headers: headers
    )
    #expect(url.absoluteString == "https://example.com/x.png?response-content-type=image/png")
    let signed = await stub.presignedURLs
    #expect(signed.count == 1)
}

@Test("stream(key:) returns a Response with content headers", .timeLimit(.minutes(2)))
func facadeStreamsResponse() async throws {
    let stub = StubDriver()
    let fileStorages = FileStorages()
    fileStorages.use(.init { _ in stub })

    let response = try await fileStorages.storage().stream(key: "hello.txt")
    #expect(response.headers.contentType?.serialize() == "text/plain")
    #expect(response.headers[.contentLength] == "5")
    let data = try await response.body.data()
    #expect(data.map { String(decoding: $0, as: UTF8.self) } == "hello")
}
