import Configuration
import Foundation
import HTTPTypes
import Testing
import Vapor
@testable import VaporUtilities

// MARK: - Helpers

private func withApp(
    config: ConfigReader? = nil,
    _ body: (Application) async throws -> Void
) async throws {
    let app: Application
    if let config {
        app = try Application(.testing, configReader: config)
    } else {
        app = try Application(.testing)
    }

    do {
        try await body(app)
        try await app.shutdown()
    } catch {
        try? await app.shutdown()
        throw error
    }
}

private func makeRequest(
    url: String,
    host: String? = nil,
    localAddress: SocketAddress? = nil
) -> Request {
    var headers = HTTPFields()
    if let host { headers[HTTPField.Name("Host")!] = host }
    return Request(
        method: .get,
        url: URI(string: url),
        headers: headers,
        localAddress: localAddress
    )
}

// MARK: - URL Configuration

@Test("URLConfiguration defaults to nil")
func configurationDefaults() {
    let config = URLConfiguration()
    #expect(config.baseURL == nil)
}

@Test("URLConfiguration accepts custom baseURL")
func configurationCustom() {
    let config = URLConfiguration(baseURL: URL(string: "https://example.com"))
    #expect(config.baseURL == URL(string: "https://example.com"))
}

@Test("URLConfiguration can be nil")
func configurationNil() {
    let config = URLConfiguration(baseURL: nil)
    #expect(config.baseURL == nil)
}

// MARK: - Application URL

@Test("Application url reads app.url from configuration", .timeLimit(.minutes(2)))
func applicationURLConfiguration() async throws {
    let provider = InMemoryProvider(values: [
        AbsoluteConfigKey(["app", "url"], context: [:]): "https://example.com"
    ])
    let config = ConfigReader(provider: provider)

    try await withApp(config: config) { app in
        #expect(app.url.baseURL == URL(string: "https://example.com"))
    }
}

@Test("Application url defaults to nil without configuration", .timeLimit(.minutes(2)))
func applicationURLConfigurationDefault() async throws {
    try await withApp { app in
        #expect(app.url.baseURL == nil)
    }
}

@Test("Application url for path with baseURL", .timeLimit(.minutes(2)))
func applicationURLWithBaseURL() async throws {
    try await withApp { app in
        let url = app.url(for: "/health", baseURL: URL(string: "https://example.com"))
        #expect(url?.absoluteString == "https://example.com/health")
    }
}

@Test("Application url for path with query", .timeLimit(.minutes(2)))
func applicationURLWithQuery() async throws {
    try await withApp { app in
        let url = app.url(
            for: "/search",
            query: ["q": "hello", "page": "1"],
            baseURL: URL(string: "https://example.com")
        )
        #expect(url != nil)
        #expect(url?.absoluteString.hasPrefix("https://example.com/search?") == true)
        #expect(url?.absoluteString.contains("q=hello") == true)
        #expect(url?.absoluteString.contains("page=1") == true)
    }
}

@Test("Application url normalises path with leading slash", .timeLimit(.minutes(2)))
func applicationURLNormalisesPath() async throws {
    try await withApp { app in
        let url = app.url(for: "health", baseURL: URL(string: "https://example.com"))
        #expect(url?.absoluteString == "https://example.com/health")
    }
}

@Test("Application url without baseURL falls back to server config", .timeLimit(.minutes(2)))
func applicationURLWithoutBaseURL() async throws {
    try await withApp { app in
        app.serverConfiguration.hostname = "127.0.0.1"
        let url = app.url(for: "/health")
        #expect(url?.absoluteString == "http://127.0.0.1/health")
    }
}

// MARK: - Request URL

@Test("Request absoluteURL with Host header", .timeLimit(.minutes(2)))
func requestAbsoluteURLWithHost() async throws {
    let request = makeRequest(url: "/users?page=1", host: "example.com")
    #expect(request.absoluteURL().absoluteString == "http://example.com/users?page=1")
}

@Test("Request absoluteURL with port in Host header", .timeLimit(.minutes(2)))
func requestAbsoluteURLWithPort() async throws {
    let request = makeRequest(url: "/", host: "example.com:8443")
    #expect(request.absoluteURL().absoluteString == "http://example.com:8443/")
}

@Test("Request absoluteURL uses baseURL when provided", .timeLimit(.minutes(2)))
func requestAbsoluteURLWithBaseURL() async throws {
    let request = makeRequest(url: "/users?page=1", host: "localhost:8080")
    let url = request.absoluteURL(baseURL: URL(string: "https://example.com"))
    #expect(url.absoluteString == "https://example.com/users?page=1")
}

@Test("Request url for path with Host header", .timeLimit(.minutes(2)))
func requestURLWithHost() async throws {
    let request = makeRequest(url: "/", host: "example.com")
    let url = request.url(for: "/login")
    #expect(url?.absoluteString == "http://example.com/login")
}

@Test("Request url for path with query", .timeLimit(.minutes(2)))
func requestURLWithQuery() async throws {
    let request = makeRequest(url: "/", host: "example.com")
    let url = request.url(for: "/login", query: ["redirect": "/profile"])
    #expect(url != nil)
    #expect(url?.absoluteString.hasPrefix("http://example.com/login?") == true)
    #expect(url?.absoluteString.contains("redirect=/profile") == true)
}

@Test("Request url uses baseURL when provided", .timeLimit(.minutes(2)))
func requestURLWithBaseURL() async throws {
    let request = makeRequest(url: "/", host: "localhost:8080")
    let url = request.url(for: "/health", baseURL: URL(string: "https://example.com"))
    #expect(url?.absoluteString == "https://example.com/health")
}

@Test("Request url normalises path with leading slash", .timeLimit(.minutes(2)))
func requestURLNormalisesPath() async throws {
    let request = makeRequest(url: "/", host: "example.com")
    let url = request.url(for: "login")
    #expect(url?.absoluteString == "http://example.com/login")
}
