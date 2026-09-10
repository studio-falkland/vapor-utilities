import Foundation
import NIOCore
import NIOFoundationCompat
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
            data: Data(buffer: file.data),
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
        FileStream(contentType: "text/plain", contentLength: 5, body: AsyncThrowingStream { $0.yield(ByteBuffer(string: "hello")); $0.finish() })
    }

    func presignedURL(key: String, method: PresignMethod, expiresIn: TimeAmount, parameters: [String: String], headers: HTTPHeaders) async throws -> URL {
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

private func withApp(_ body: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    try await body(app)
    try await app.asyncShutdown()
}

private func makeRequest(_ app: Application) -> Request {
    Request(application: app, method: .GET, url: URI(path: "/"), on: app.eventLoopGroup.next())
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
    try await withApp { app in
        let stub = StubDriver()
        app.fileStorages.use(.init { _ in stub })
        let required = app.fileStorages.require()
        #expect(required as? StubDriver === stub)
    }
}

@Test("drivers registered under a named id are returned by require(id)", .timeLimit(.minutes(2)))
func registryNamedDriver() async throws {
    try await withApp { app in
        let stub = StubDriver()
        let id = FileStorageID(string: "archives")
        app.fileStorages.use(.init { _ in stub }, as: id)
        #expect(app.fileStorages.require(id) as? StubDriver === stub)
    }
}

@Test("require builds a driver at most once", .timeLimit(.minutes(2)))
func registryDriverIsLazyAndCached() async throws {
    try await withApp { app in
        let stub = StubDriver()
        app.fileStorages.use(.init { _ in stub })
        #expect((app.fileStorages.require() as? StubDriver) === (app.fileStorages.require() as? StubDriver))
    }
}

@Test("req.fileStorage routes to the default driver", .timeLimit(.minutes(2)))
func requestFileStorageAccess() async throws {
    try await withApp { app in
        let stub = StubDriver()
        app.fileStorages.use(.init { _ in stub })
        let fs = makeRequest(app).fileStorage
        try await fs.upload(data: Data("bytes".utf8), key: "a/b.txt", contentType: "text/plain")
        let uploaded = await stub.uploadedData
        #expect(uploaded.count == 1)
        #expect(uploaded[0].key == "a/b.txt")
        #expect(uploaded[0].contentType == "text/plain")
        #expect(uploaded[0].data == Data("bytes".utf8))
    }
}

@Test("req.fileStorage(id:) routes to a named driver", .timeLimit(.minutes(2)))
func requestFileStorageNamedAccess() async throws {
    try await withApp { app in
        let stub = StubDriver()
        let id = FileStorageID(string: "archives")
        app.fileStorages.use(.init { _ in stub }, as: id)
        let fs = makeRequest(app).fileStorage(id)
        try await fs.delete(key: "old.tar.gz")
        let deleted = await stub.deletedKeys
        #expect(deleted == ["old.tar.gz"])
    }
}

@Test("drivers are shut down during application shutdown", .timeLimit(.minutes(2)))
func registryDriversShutDown() async throws {
    let app = try await Application.make(.testing)
    let stub = StubDriver()
    app.fileStorages.use(.init { _ in stub })
    _ = app.fileStorages.require()
    try await app.asyncShutdown()
    let count = await stub.shutdownCount
    #expect(count == 1)
}

@Test("concurrent first access builds exactly one shared driver", .timeLimit(.minutes(2)))
func registryConcurrentFirstAccessBuildsOnce() async throws {
    try await withApp { app in
        let counter = StubFactoryCounter()
        let stub = StubDriver()
        app.fileStorages.use(.init { _ in
            counter.increment()
            return stub
        })

        let required: [any FileStorageDriver] = await withTaskGroup(
            of: (any FileStorageDriver).self,
            returning: [any FileStorageDriver].self
        ) { group in
            for _ in 0..<32 {
                group.addTask { app.fileStorages.require() }
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
}

// MARK: - Façade

@Test("upload(file:) uses the file content type when none is given", .timeLimit(.minutes(2)))
func facadeUploadsFile() async throws {
    try await withApp { app in
        let stub = StubDriver()
        app.fileStorages.use(.init { _ in stub })
        let file = File(data: "pdf", filename: "report.pdf")
        try await makeRequest(app).fileStorage.upload(file: file, key: "docs/report.pdf")
        let uploaded = await stub.uploadedData
        #expect(uploaded.count == 1)
        #expect(uploaded[0].contentType == "application/pdf")
        #expect(uploaded[0].data == Data("pdf".utf8))
    }
}

@Test("presignedURL forwards parameters and headers to the driver", .timeLimit(.minutes(2)))
func facadePresignedURL() async throws {
    try await withApp { app in
        let stub = StubDriver()
        app.fileStorages.use(.init { _ in stub })
        let url = try await makeRequest(app).fileStorage.presignedURL(
            key: "x.png",
            method: .get,
            expiresIn: .minutes(5),
            parameters: ["response-content-type": "image/png"],
            headers: ["Content-Type": "image/png"]
        )
        #expect(url.absoluteString == "https://example.com/x.png?response-content-type=image/png")
        let signed = await stub.presignedURLs
        #expect(signed.count == 1)
    }
}

@Test("stream(key:) returns a Response with content headers", .timeLimit(.minutes(2)))
func facadeStreamsResponse() async throws {
    try await withApp { app in
        let stub = StubDriver()
        app.fileStorages.use(.init { _ in stub })
        let response = try await makeRequest(app).fileStorage.stream(key: "hello.txt")
        #expect(response.headers.contentType?.serialize() == "text/plain")
        #expect(response.headers.first(name: .contentLength) == "5")
        let byteBuffer = try await response.body.collect(on: app.eventLoopGroup.next()).get()
        #expect(String(buffer: byteBuffer ?? ByteBuffer()) == "hello")
    }
}